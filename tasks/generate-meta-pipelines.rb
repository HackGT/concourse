require 'yaml'
require 'erb'
require_relative './lib.rb'

# parameters
team      = get_env 'PIPEDREAM_TEAM'
out_dir   = get_env 'PIPEDREAM_OUT_DIR'
out_file  = get_env 'PIPEDREAM_OUT_FILE'
biodomes  = get_env 'PIPEDREAM_BIODOMES_DIR'

# constants
SOURCE_DIR = File.expand_path(File.dirname(__FILE__))
BASE_PIPE = File.join SOURCE_DIR, '../pipelines/meta.yaml'
META_TEMPLATE = File.join SOURCE_DIR, '../templates/meta-pipeline.yaml'
pipeline_path = File.join out_dir, '0001-gen-pipeline.yaml'
secrets_file = File.join out_dir, 'secrets.yaml'

# collect all the secrets
secrets = collect_prefixes ENV, 'secret_'

# build the new meta pipeline
meta_pipeline = Dir[File.join biodomes, '*']
  .map do |dome_file|
    biodome = YAML.load (File.read dome_file)
    biodome[:biodome] = basename_no_ext dome_file
    biodome[:secrets] = secrets.keys
    YAML.load (ERB.new(File.read META_TEMPLATE).result(binding))
  end
  .reduce(load_yaml (File.read BASE_PIPE)) { |memo, aug| merge_pipelines memo, aug }

# pipelines description
pipelines_desc = {
  'pipelines' => [
    'name' => 'meta',
    'team' => team,
    'config_file' => pipeline_path,
    'vars_files' => [secrets_file],
  ],
}

# write everything to disk
[
  [pipeline_path, meta_pipeline, true],
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
