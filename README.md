r10k_payload_deploy
===================

deploy r10k environments based on payloads from github web hooks

takes a webhooks payload and parses it for pertinent info, then deploys to all puppet masters via mcollective.

this incarnation is amedia specific as it makes assumptions about naming conventions of environments.

we expect to find the mco r10k application on this end, and the agent on all
puppet masters

mco agents blatantly stolen from <https://github.com/acidprime/r10k> and
slightly modified to fit our workflow

webhook
-------

set the webhook up in git with a shared secret, application/json, url
<yourserver>:<yourport>/payload, and check the box 'Just the push event'

config
------

you'll want a defaults file for the initscript to load:

        SHA1_SECRET=94d444f4f9194533c190cfb7b5fd4d38ee536aad
        
        PORT=8443
        BIND="::"
        
        SSL_CRT=/etc/ssl/certs/ssl-cert-snakeoil.pem
        SSL_KEY=/etc/ssl/private/ssl-cert-snakeoil.key
        
        LOGFILE=/var/log/r10k_payload_deploy.log
        PIDFILE=/var/run/r10k_payload_deploy.pid
        
        DAEMON=/opt/r10k_payload_deploy/app.rb
