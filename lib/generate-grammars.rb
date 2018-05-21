#!/usr/bin/env ruby

require 'json'
require 'faraday'

def get_service_map
  download = Faraday.get 'https://awsiamconsole.s3.amazonaws.com/iam/assets/js/bundles/policies.js'
  File.write './policies.js', download.body
end

def parse_service_map
  policies = File.read('./policies.js')
  # Extract the ServiceMap
  index = policies.index 'serviceMap'
  chars = policies[index..-1].split ''
  # Pull the following object
  obj = []
  lb = rb = 0
  chars.each do |c|
    lb += 1 if c == '{'
    rb += 1 if c == '}'
    obj.push c
    break if (lb > 0) && (lb == rb)
  end
  # Turn Javascript Object into JSON (FML -- can't aws just give us the JSON?)
  service_map = obj.join.gsub(/\s/, '')
  # Cleanup Exceptions
  service_map.gsub!(/HasResource:\!([0-9]+)/, 'HasResource:"!\1"')
  service_map.gsub!(/ARNRegex:("[^"]*")/, 'ARNRegex:"REMOVED"')
  # turn objects into strings e.g. test:[] => "test":[]
  service_map.gsub!(/([a-zA-Z0-9_]+):([\[{0-9"])/, '"\1":\2')
  service_map = '{' + service_map + '}'
  File.write('service_map.json', service_map)
  JSON.load(service_map)
end

def generate_grammar(service_map)
  # extract fields
  cson = File.read './policy.cson'
  # service_count = service_map['serviceMap'].keys.length

  # Get Services
  prefixes = service_map['serviceMap'].values.collect { |v| v['StringPrefix'] }
  service_list = prefixes.join('|').downcase
  cson.gsub! '{{SERVICE_LIST}}', service_list
  puts service_list

  # Get Actions
  actions = service_map['serviceMap'].values.collect { |v| v['Actions'] }.flatten
  action_list = actions.join('|').downcase
  cson.gsub! '{{ACTION_LIST}}', action_list
  puts action_list

  File.write '../grammars/generated-policy.cson', cson
end

def get_service_snippet(service, actions)
  snippet = []
  snippet.push "  'All #{service} Actions':"
  snippet.push "    'prefix': '#{service}:'"
  snippet.push "    'body': \"\"\""
  actions.each do |a|
    snippet.push "      \"#{service}:#{a}\","
  end
  snippet.push "    \"\"\"\n\n"
  snippet.join "\n"
end

def generate_snippets(service_map)
  cson = File.read './snippets.cson'

  actions_for_service = {}
  service_map['serviceMap'].keys.each do |k|
    service = service_map['serviceMap'][k]['StringPrefix']
    actions = service_map['serviceMap'][k]['Actions']
    actions_for_service[service] = [] if actions_for_service[service].nil?
    actions_for_service[service].concat actions
  end

  actions_for_service.each do |service, actions|
    snippet = get_service_snippet service, actions
    cson += snippet
  end

  File.write '../snippets/generated-snippets.cson', cson
end

get_service_map
service_map = parse_service_map
# Grammar
generate_grammar service_map
# Snippets
generate_snippets service_map
