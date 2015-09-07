#!/usr/bin/env ruby
#
# Ørjan Ommundsen <orjan@redpill-linpro.com>
#

require 'rubygems'
require 'daemon'
require 'bundler/setup'
require 'sinatra'
require 'thin'
require 'json'
require 'yaml'
require 'mcollective'

puts "Starting up"

unless ARGV[0] then
  abort("Provide us with a config file")
end

$config  = File.open( ARGV[0], 'r') { |fo| YAML.load( fo ) }

class MyThinBackend < ::Thin::Backends::TcpServer
  def initialize(host, port, options)
    super(host, port)
    @ssl = true
    @ssl_options = options
  end
end

configure do
  set :environment, :production
  set :bind, $config['bind']
  set :port, $config['port']
  set :server, "thin"
  set :daemon, true
  class << settings
    def server_settings
      {
        :backend          => MyThinBackend,
        :private_key_file => File.dirname(__FILE__) + "/" + $config['ssl_key'],
        :cert_chain_file  => File.dirname(__FILE__) + "/" + $config['ssl_crt'],
        :verify_peer      => false
      }
    end
  end
end

include MCollective::RPC

post '/payload' do
  request.body.rewind
  payload_body = request.body.read
  verify_signature(payload_body)
  push = JSON.parse(payload_body)

  a = analyze_payload(push)

  puts "#{a['commit_id']}: received payload with changes for branch #{a['branch_name']} of repo #{a['repository_name']}"
  puts "                   url: #{a['commit_url']}"
  puts "                   commiter: #{a['commit_author']} <#{a['commit_email']}>"
  puts "		   message: #{a['commit_message']}"
  puts "#{a['commit_id']}: will deploy environment #{a['r10k_full_name']}"

  mco_deploy(a['r10k_full_name'], a['commit_id'], changed_puppetfile(push))
  
end

def verify_signature(payload_body)
  signature = 'sha1=' + OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new('sha1'), $config['sha1_secret'], payload_body)
  return halt 500, "Signatures didn't match!" unless Rack::Utils.secure_compare(signature, request.env['HTTP_X_HUB_SIGNATURE'])
end

def analyze_payload(payload_body)

  @info = Hash.new

  @info['branch_name'] = payload_body['ref'].split('/').last # "ref": "refs/heads/ipv6" gives 'ipv6' as branch
  @info['commit_id'] = payload_body['head_commit']['id'] 
  @info['commit_message'] = payload_body['head_commit']['message'] 
  @info['commit_author'] = payload_body['head_commit']['committer']['name'] 
  @info['commit_email'] = payload_body['head_commit']['committer']['email'] 
  @info['commit_url'] = payload_body['head_commit']['url'] 
  @info['repository_name'] = payload_body['repository']['name']
  @info['r10k_shortname'] = payload_body['repository']['name'].split('-').last # puppet-env-front gives 'front'
  @info['r10k_full_name'] = "api_#{@info['r10k_shortname']}_#{@info['branch_name']}"

  return @info
end

def changed_puppetfile(payload_body)
  payload_body['head_commit']['modified'].include?('Puppetfile')
end

def mco_deploy(name, commit_id, modules)
  @mc = rpcclient("r10k")
  @mc.progress = false
  if modules 
    printf("%s: Deploying environment %s with changed Puppetfile, updating modules on all puppet masters\n", commit_id, name)
    printf("%s:", commit_id)
    @stats = @mc.deploy_with_modules(:environment => name).each do |resp|
      printf("%s: %s ", resp[:sender], resp[:statusmsg])
    end
    puts
  else
    printf("%s: Puppetfile unchanged, deploying environment %s, but not deploying modules\n", commit_id, name)
    printf("%s:", commit_id)
    @stats = @mc.deploy(:environment => name).each do |resp|
      printf("%s: %s ", resp[:sender], resp[:statusmsg])
    end
    puts
  end
  @mc.disconnect
end

Daemon.daemonize($config['pidfile'], $config['logfile'])
