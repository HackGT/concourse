#!/usr/bin/env ruby
require 'optparse'
require 'yaml'
require 'json'
require 'erb'
require 'uri'

#############
# CLI STUFF #
#############
DEFAULT_BRANCH = "master"
SECRETS_FILE = "secrets.yaml"
SOURCE_DIR = File.expand_path(File.dirname(__FILE__))
APP_TEMPLATE = File.join SOURCE_DIR, '../templates/app-pipeline.yaml.erb'
PIPELINE_TEMPLATE = File.join SOURCE_DIR, '../templates/pipeline.yaml.erb'

options = {}
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



################
# MAIN PROGRAM #
################
class Pipeline
  def self.merge_pipelines main, augment
    ['resources', 'resource_types', 'jobs', 'groups'].each do |header|
      # combine the two, remove duplicates
      main[header] = (main[header] || []) | (augment[header] || [])
    end
    main
  end


  def self.git_to_shortname git_url
    uri = URI.parse git_url
    uri.path.chomp(File.extname(uri.path)).sub(/^\//, '')
  end


  def self.build_app_pipeline app
    YAML.load ERB.new(File.read APP_TEMPLATE).result(binding)
  end


  def self.build_pipeline config, config_path
    # get metadata of the pipeline file
    full_config_path = File.expand_path config_path
    pipeline = Dir.chdir(File.expand_path(File.dirname config_path)) {
      {
        :git_ref => `git show-ref --head -s -- HEAD | head -1`,
        :git_path => `git ls-tree --full-name --name-only HEAD #{full_config_path}`,
        :git_remote => `git config --get remote.origin.url`,
        :charts => config['apps'].select {|a| a.include? 'helm'},
        :runnables => config['apps'].select {|a| a.include? 'run'},
      }
    }
    pipe_cfg = YAML.load ERB.new(File.read PIPELINE_TEMPLATE).result(binding)

    # add individual steps for each app
    config['apps']
      .map { |app| Pipeline.build_app_pipeline app }
      .reduce(pipe_cfg) { |memo, aug| Pipeline.merge_pipelines memo, aug }
  end
end


def dump_yaml data
  output = YAML.dump data
  # ruby puts template vars as "{{var}}"
  # but concourse only wants them as {{var}} for some reason
  output.gsub(/("|')(\{\{.+\}\})("|')/, '\2')
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
      config_path = File.join options[:domes_dir], dome
      config_text = File.read config_path
      config = YAML.load config_text
      config['name'] = File.basename(dome, File.extname(dome))
      # make a pipeline config out of it
      pipeline = Pipeline.build_pipeline config, config_path
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
