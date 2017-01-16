#!/usr/bin/env ruby
require 'optparse'
require 'yaml'
require 'json'

DEFAULT_BRANCH = "master"
SECRETS_FILE = "secrets.yaml"

options = {}


class Pipeline
  def self.merge_pipelines main, augment
    [
      'resources',
      'resource_types',
      'jobs',
      'groups',
    ]
    .each do |header|
      # combine the two, remove duplicates
      main[header] = main[header] | augment[header]
    end
    main
  end


  def self.build_app_pipeline app
    app_name = File.basename app['name']

    pipeline = {
      'resources' => [
        # make sure we have a copy of the code
        {
          'name' => app_name,
          'type' => 'git',
          'source' => {
            'uri' => "https://github.com/#{app['name']}.git",
            'branch' => (app.include?('branch') ? app['branch'] : DEFAULT_BRANCH),
          }
        },
        # define the final place to put the built image
        {
          'name' => "#{app_name}-image",
          'type' => 'docker-image',
          'source' => {
            'repository' => app['name'],
            'email' => '{{dockerhub_email}}',
            'username' => '{{dockerhub_user}}',
            'password' => '{{dockerhub_pass}}',
          },
        },
      ],
      'jobs' => [],
    }

    # TODO: when we have something with tests, this section will add a testing
    # step to the process, for now just build it

    # Step: build docker image and push to docker hub
    pipeline['jobs'].push({
      'name' => "#{app_name}-build-image",
      'plan' => [
        {
          'get' => app_name,
          'trigger' => true,
        },
        {
          'put' => "#{app_name}-image",
          'params' => {
            'build' => app_name,
          },
          'get_params' => {
            'skip_download' => true,
          },
        },
      ],
    })

    pipeline
  end


  def self.build_pipeline config
    # add individual steps for each app
    pipeline = config['apps']
      .map { |app| Pipeline.build_app_pipeline app }
      .reduce { |memo, aug| Pipeline.merge_pipelines memo, aug }

    # TODO: add step to add everything to k8s

    pipeline
  end
end


def dump_yaml data
  output = YAML.dump data
  # ruby puts template vars as "{{var}}"
  # but concourse only wants them as {{var}} for some reason
  output.gsub(/("|')(\{\{.+\}\})("|')/, '\2')
end

required = []

# parse command line options
OptionParser.new do |parser|
  # get the domes dir
  parser.on('-d', '--domes-dir dir', 'Directory of the biodome files.') do |v|
    options[:domes_dir] = v
  end
  required.push :domes_dir

  # get the output pipelines dir
  parser.on('-p', '--pipelines-file file', 'Pipelines file to write to.') do |v|
    options[:pipelines_file] = v
  end
  required.push :pipelines_file

  # get the team name to build the pipeline on
  parser.on('-t', '--team name', 'Which team to use.') do |v|
    options[:team_name] = v
  end
  required.push :team_name

  # get the team name to build the pipeline on
  parser.on('-w', '--working-dir dir', 'Dir to prefix when using relative paths.') do |v|
    options[:pwd] = v
  end
  required.push :pwd
end.parse!

# all args are required
if required.any? { |a| options[a].nil? }
  raise ArgumentError, "all arguments must be specified."
end

# create a secrets file with all the secret params
secrets = ENV
  .select { |name| /^secret_/ =~ name }
  .reduce({}) do |memo, name|
    memo[name[0].gsub(/^secret_/, '')] = name[1]
    memo
  end
File.write SECRETS_FILE, (dump_yaml secrets)

# for each yaml file found make a pipeline
pipelines = Dir
  .entries(options[:domes_dir])
  .select { |f| /(\.yaml|\.yml)$/ =~ f }
  .map do |dome|
      # parse the config file
      config_text = File.read(File.join options[:domes_dir], dome)
      config = YAML.load config_text
      config['name'] = File.basename(dome, File.extname(dome))
      # make a pipeline config out of it
      pipeline = Pipeline.build_pipeline config
      # path we're gonna give to the general config
      pipeline_path = "pipeline-#{config['name']}.yaml"
      # dump the yaml into a file and return the path
      pipeline_config = dump_yaml pipeline
      puts pipeline_config
      File.write pipeline_path, (pipeline_config)
      # create the config for the pipeline
      {
        'name' => config['name'],
        'team' => options[:team_name],
        'config_file' => File.join(options[:pwd], pipeline_path),
        'vars_files' => [File.join(options[:pwd], SECRETS_FILE)],
      }
    end
  .to_a

pipelines_config = dump_yaml ({
  'pipelines' => pipelines,
})
puts pipelines_config
File.write options[:pipelines_file], pipelines_config
