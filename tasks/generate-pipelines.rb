require 'yaml'
require 'erb'
require_relative './lib.rb'

# parameters
team          = get_env 'PIPEDREAM_TEAM'
out_dir       = get_env 'PIPEDREAM_OUT_DIR'
out_file      = get_env 'PIPEDREAM_OUT_FILE'
biodome_file  = get_env 'PIPEDREAM_BIODOME_FILE'

# constants
MAX_PORT = 65535
SOURCE_DIR = File.expand_path(File.dirname(__FILE__))
TEMPLATES_DIR = File.join SOURCE_DIR, '../templates/'
PIPELINE_TEMPLATE = File.join SOURCE_DIR, '../templates/pipeline.yaml.erb'
pipeline_path = File.join out_dir, '0001-gen-pipeline.yaml'
secrets_file = File.join out_dir, 'secrets.yaml'

class Pipeline
  def initialize config, biodome_file, secrets
    @biodome_file = File.expand_path biodome_file
    @pipeline = {}
    @unique_port = 1024 - 1

    # collect pipeline data
    @data = {
      'charts' => config['apps'].select {|a| a.include? 'helm'},
      'runnables' => config['apps'].select {|a| a.include? 'run'},
      'git_apps' => config['apps'].select {|a| a.include? 'git'},
      'src_apps' => config['apps'].select {|a| Dir.exists? a['name']},
      'biodome' => config,
      'secrets' => secrets.keys,
    }

    # collect bidome-specific data
    @data.merge!(Dir.chdir(File.dirname @biodome_file) {
      {
        'name' => (basename_no_ext @biodome_file),
        'git_ref' => `git rev-parse HEAD`,
        'git_path' => `git ls-tree --full-name --name-only HEAD #{@biodome_file}`,
        'git_remote' => `git config --get remote.origin.url`,
      }
    })

    # get the git version of each app (git apps must also be src_apps)
    @data['git_apps'].each do |app|
      app.merge!(Dir.chdir(app['name']) {
        {
          'git_ref' => `git rev-parse HEAD`,
        }
      })
    end

    # for convenience, load all config files
    self.in_each_app do |app|
      app['config'] = (Dir['*.yaml'] + Dir['*.yml']).reduce({}) do |data, file|
        data[(basename_no_ext file)] = YAML.load (File.read file)
        data
      end
    end
  end

  def [](key)
    @data[key.to_s]
  end

  def in_each_app
    @data['src_apps'].each do |app|
      Dir.chdir(app['name']) do
        @app_context = app
        yield app
      end
    end
    @app_context = nil
  end

  def add template_name
    augment = YAML.load (self.load template_name)
    @pipeline = merge_pipelines @pipeline, augment
  end

  def get_unique_port
    if @unique_port > MAX_PORT
      raise 'used up too many unique ports'
    else
      @unique_port += 1
    end
  end

  def load template_name
    pipeline = self
    app = @app_context
    template = Dir["#{TEMPLATES_DIR}/#{template_name}.*"][0]
    ERB.new(File.read template).result(binding)
  end

  def load_with template_name, context
    pipeline = self
    app = context
    template = Dir["#{TEMPLATES_DIR}/#{template_name}.*"][0]
    ERB.new(File.read template).result(binding)
  end

  def indent spaces, text
    text.lines
      .map { |l| (' ' * spaces) + l }
      .join
  end

  def generated
    @pipeline
  end
end

# collect all the secrets
secrets = collect_prefixes ENV, 'secret_'

# load biodome data
config = YAML.load (File.read biodome_file)

# make a pipeline description
pipeline = Pipeline.new config, biodome_file, secrets

# pipelines description
pipelines_desc = {
  'pipelines' => [
    'name' => pipeline[:name],
    'team' => team,
    'config_file' => pipeline_path,
    'vars_files' => [secrets_file],
  ],
}

# evaluate config dsl
eval((File.read (File.join SOURCE_DIR, '../config/all.rb')), binding)

# write everything to disk
[
  [pipeline_path, pipeline.generated, true],
  [secrets_file, secrets, false],
  [(File.join out_dir, out_file), pipelines_desc, true],
]
.each do |path, data, display|
  dumped = dump_yaml data
  File.write path, dumped
  if display
    puts
    puts path
    puts dumped
  end
end
