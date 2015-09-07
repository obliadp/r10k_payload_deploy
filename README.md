# r10k_payload_deploy
deploy r10k environments based on payloads from github web hooks

takes a webhooks payload and parses it for pertinent info, then deploys to all puppet masters via mcollective.

this incarnation is amedia specific as it makes assumptions about naming conventions of environments.

we expect to find the mco r10k plugin on this end, and also on all
puppet masters

'''mco agents blatantly stolen from https://github.com/acidprime/r10k and
slightly modified to fit our workflow'''

=== config ===

you'll want a config.yml:
 ---
 # same as your github webhook
 sha1_secret: xxxxxxxxxx

 # where to bind
 port: 8443
 bind: '::'

 # certs. if you use snake oil, turn off verification in github webhook
 ssl_crt: server.crt
 ssl_key: server.key

 # ssia
 logfile: /var/log/r10k_payload_deploy.log
 pidfile: /var/run/r10k_payload_deploy.pid

