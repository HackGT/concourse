#!/usr/bin/env ruby
require 'yaml'
require 'erb'
require 'uri'

SOURCE_DIR = File.expand_path(File.dirname(__FILE__))
KUBE_TEMPLATE = File.join SOURCE_DIR, '../templates/kube-deploy.yaml.erb'
PORT_RANGE = 1024..65535

output_file = ENV['OUTPUT_FILE'] || (raise 'must specify output file')
biodome_file = ENV['BIODOME_FILE'] || (raise 'must specify biodome file')
biodome_config = YAML.load File.read(biodome_file)

apps = biodome_config['apps']
  .select { |a| a.include? 'run' }
  .zip(PORT_RANGE)
  .map do |a, port|
    app = {}
    git = URI.parse a['git']
    app[:dockerhub] = git.path.chomp(File.extname(git.path)).sub(/^\//, '').downcase
    app[:name] = a['name'] || (raise 'app must have a name!')
    app[:port] = a['run']['port'] || (raise 'app must define a port!')
    app[:protocol] = a['run']['protocol'] || 'TCP'
    app[:unique_port] = port
    app
  end

env = biodome_config['apps']
  .select { |a| a.include? 'provides' }
  .map { |a| a['provides'] }
  .reduce &:merge

deployment = {
  :env => env,
  :apps => apps,
}

output = ERB.new(File.read KUBE_TEMPLATE).result(binding)
puts output
File.write output_file, output
