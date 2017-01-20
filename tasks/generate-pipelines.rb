require 'yaml'
require 'erb'
require_relative './lib.rb'

# parameters
team          = get_env 'PIPEDREAM_TEAM'
out_dir       = get_env 'PIPEDREAM_OUT_DIR'
out_file      = get_env 'PIPEDREAM_OUT_FILE'
biodome_file  = get_env 'PIPEDREAM_BIODOME_FILE'

# constants
SOURCE_DIR = File.expand_path(File.dirname(__FILE__))
PIPELINE_TEMPLATE = File.join SOURCE_DIR, '../templates/pipeline.yaml.erb'
pipeline_path = File.join out_dir, '0001-gen-pipeline.yaml'
secrets_file = File.join out_dir, 'secrets.yaml'
biodome_path = File.expand_path biodome_file

# collect all the secrets
secrets = collect_prefixes ENV, 'secret_'

# load biodome data
config = YAML.load (File.read biodome_file)

# collect pipeline data
pipeline = {
    :charts => config['apps'].select {|a| a.include? 'helm'},
    :runnables => config['apps'].select {|a| a.include? 'run'},
    :git_apps => config['apps'].select {|a| a.include? 'git'},
    :name => (basename_no_ext biodome_file),
    :biodome => config,
}
pipeline = pipeline.merge(Dir.chdir(File.dirname biodome_path) {
  {
    :git_ref => `git show-ref --head -s -- HEAD | head -1`,
    :git_path => `git ls-tree --full-name --name-only HEAD #{biodome_path}`,
    :git_remote => `git config --get remote.origin.url`,
  }
})
pipeline[:git_apps].each do |app|
  app[:git_ref] = Dir.chdir(app['name']) {
    `git show-ref --head -s -- HEAD | head -1`
  }
end

# get the yaml
pipe_cfg = YAML.load ERB.new(File.read PIPELINE_TEMPLATE).result(binding)

# pipelines description
pipelines_desc = {
  'name' => pipeline[:name],
  'team' => team,
  'config_file' => pipeline_path,
  'vars_files' => [secrets_file],
}

# write everything to disk
[
  [pipeline_path, pipe_cfg],
  [secrets_file, secrets],
  [(File.join out_dir, out_file), pipelines_desc],
]
.each do |path, data|
  dumped = dump_yaml data
  File.write path, dumped
  puts
  puts path
  puts dumped
end
