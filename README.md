
Sinatra on OpenShift
====================

This git repository helps you get up and running quickly w/ a Sinatra installation
on OpenShift.


Running on OpenShift
----------------------------

Create an account at http://openshift.redhat.com/

Create a ruby-1.9 application

    rhc app create -a sinatra -t ruby-1.9

Add this upstream sinatra repo

    cd sinatra
    git remote add upstream -m master git://github.com/openshift/sinatra-example.git
    git pull -s recursive -X theirs upstream master
    
Then push the repo upstream

    git push

That's it, you can now checkout your application at:

    http://sinatra-$yournamespace.rhcloud.com


Running this application locally
----------------------------------

To run this application locally, cd into the sinatra-example directory that you cloned and run

    ruby app.rb

Or you can use this command to run the Modular/Object based version located in app.modular.rb

    ruby app.modular.rb

If you would like to run the Modular/Object based code on OpenShift just follow the below instructions:

1. reanme app.rb to app.classic.rb
2. rename config.ru to config.classic.ru
3. rename app.modular.rb to app.rb
4. rename config.modular.ru to config.ru

Then you just need to commit your changes and git push them to OpenShift


License
-------

This code is dedicated to the public domain to the maximum extent
permitted by applicable law, pursuant to CC0
http://creativecommons.org/publicdomain/zero/1.0/
