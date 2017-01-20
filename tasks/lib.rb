require 'uri'

DEFAULT_BRANCH = 'master'

def get_env name
  ENV[name] || (raise "You must specify the env var #{name}.")
end

def git_to_shortname git_url
  uri = URI.parse git_url
  uri.path.chomp(File.extname(uri.path)).sub(/^\//, '')
end

def dockerhub_from_git git_url
  git_to_shortname(git_url).downcase
end

def merge_pipelines main, augment
  ['resources', 'resource_types', 'jobs', 'groups'].each do |header|
    # combine the two, remove duplicates
    main[header] = (main[header] || []) | (augment[header] || [])
  end
  main
end

def basename_no_ext file
  File.basename(file, File.extname(file))
end

# create a secrets file with all the secret params
def collect_prefixes hash, prefix
  prefix_matcher = Regexp.new("^#{prefix}")
  hash
    .select { |name| prefix_matcher =~ name }
    .reduce({}) do |memo, name|
      memo[name[0].gsub(prefix_matcher, '')] = name[1]
      memo
    end
end

def dump_yaml data
  output = YAML.dump data
  # ruby puts template vars as "{{var}}"
  # but concourse only wants them as {{var}} for some reason
  output.gsub(/("|')(\{\{.+\}\})("|')/, '\2')
end

def load_yaml text
  # ruby puts template vars as "{{var}}"
  # but concourse only wants them as {{var}} for some reason
  YAML.load text.gsub(/(\{\{.+\}\})/, '"\0"')
end
