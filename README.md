Sinatra on OpenShift
====================

This git repository helps you get up and running quickly w/ a Sinatra installation on OpenShift.


Running on OpenShift
----------------------------

Create an account at http://openshift.redhat.com/

Create a ruby-1.9 application

    rhc app create -a sinatra -t ruby-1.9

Add this upstream sinatra repo

    cd sinatra
    git remote add upstream -m master git://github.com/openshift/sinatra-example.git
    git pull -s recursive -X theirs upstream master
    
Then push the repo back to your OpenShift gear

    git push origin master

That's it, you can now checkout your application at

    http://sinatra-$yournamespace.rhcloud.com

You can also create a gear using this code as the base using the following command

		rhc create-app -a <appname> -t ruby-1.9 --from-code git://github.com/openshift/sinatra-example.git
		
Or by clicking the "Change" link next to Source Code when creating a new ruby-1.9 application and pasting the git repository url into the field that appears


Configuring the Modular/Object or views code to run on OpenShift
----------------------------------

If you would like to run the Modular/Object based, or views code on OpenShift just follow the below instructions:

1. reanme app.rb to app.classic.rb
2. rename config.ru to config.classic.ru
3. rename [app.modular.rb/app.views.rb/app.modular.views.rb] to app.rb
4. rename [config.modular.ru/config.views.ru/config.modular.views.ru] to config.ru

Then you just need to commit your changes and git push them to your OpenShift gear


Running this application locally
----------------------------------

Before running any of these commands, you should run the below command to make sure that you have the correct ruby gems installed

		bundle install

To run this application locally, cd into the sinatra-example directory that you cloned and run

		ruby app.rb

Or you can use this command to run the Modular/Object based version located in app.modular.rb

		ruby app.modular.rb

Also included are examples of how to use erb views with both the regular and Modular/Object based versions of Sinatra
You can run either of those using the following commands

		ruby app.views.rb
		ruby app.modular.views.rb
		



License
-------

This code is dedicated to the public domain to the maximum extent
permitted by applicable law, pursuant to CC0
http://creativecommons.org/publicdomain/zero/1.0/
