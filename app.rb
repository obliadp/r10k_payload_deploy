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

class MyThinBackend < ::Thin::Backends::TcpServer
  def initialize(host, port, options)
    super(host, port)
    @ssl = true
    @ssl_options = options
  end
end

configure do
  set :environment, :production
  set :bind, ENV['BIND']
  set :port, ENV['PORT']
  set :server, "thin"
  set :daemon, true
  class << settings
    def server_settings
      {
        :backend          => MyThinBackend,
        :private_key_file => ENV['SSL_KEY'],
        :cert_chain_file  => ENV['SSL_CRT'],
        :verify_peer      => false
      }
    end
  end
end

include MCollective::RPC

Daemon.daemonize(ENV['PIDFILE'], ENV['LOGFILE'])

post '/payload' do
  request.body.rewind
  payload_body = request.body.read
  verify_signature(payload_body)
  payload = JSON.parse(payload_body)
  verify_event_type(payload)

  a = analyze_payload(payload)

  @_commit_id = a['commit_id'][0..5]

  puts "#{@_commit_id}: received payload with changes for branch #{a['branch_name']} of repo #{a['repository_name']}"
  puts "        url: #{a['commit_url']}"
  puts "        commiter: #{a['commit_author']} || message: #{a['commit_message']}"

  mco_deploy(a['r10k_full_name'], @_commit_id, deploy_puppetfile(payload))
end

def verify_signature(payload_body)
  signature = 'sha1=' + OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new('sha1'), ENV['SHA1_SECRET'], payload_body)
  return halt 500, "Signatures didn't match!" unless Rack::Utils.secure_compare(signature, request.env['HTTP_X_HUB_SIGNATURE'])
end

def verify_event_type(payload_body)
  # if not a push event, return 200OK and do nothing
  return halt 202, "event type not handled atm, but that's okay. see #{payload_body['head_commit']['url']} for details" if payload_body['pusher'].nil?
end

def analyze_payload(payload_body)
  @info = Hash.new
  @info['branch_name'] = payload_body['ref'].split('/').last # "ref": "refs/heads/ipv6" gives 'ipv6' as branch
  @info['created'] = payload_body['created']
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

def deploy_puppetfile(payload_body)
  # if Puppetfile is modified, or if this is a new branch, deploy with '-p'
  return true if (payload_body['head_commit']['modified'].include?('Puppetfile') || payload_body['created'])
end

def mco_deploy(name, commit_id, modules)
  @mc = rpcclient("r10k")
  @mc.progress = false
  printf("%s: Deploying environment %s %s modules\n", commit_id, name, (modules ? 'with' : 'without'))
  @stats = @mc.deploy_with_modules(:environment => name).each do |resp|
    printf("%s: %-20s: %s\n", commit_id, resp[:sender], resp[:statusmsg])
  end
  @mc.disconnect
end

