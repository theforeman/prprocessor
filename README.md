# PR Processor

The PR processor is a [Github Application](https://developer.github.com/apps/) using the [octomachinery](https://github.com/sanitizers/octomachinery) framework.

## Configuring

Follow the [octomachinery tutorial](https://tutorial.octomachinery.dev/en/latest/octomachinery-for-github-apps.html#create-a-new-github-app) to configure the Github application. Then the following values can be set in the environment:

* `GITHUB_APP_IDENTIFIER` - The Github application ID
* `GITHUB_PRIVATE_KEY` - The Github private key
* `GITHUB_WEBHOOK_SECRET` - The Github secret, if any
* `REDMINE_URL` - The Redmine URL
* `REDMINE_KEY` - The Redmine API key

* `HOST` - Defaults to `0.0.0.0`, can be set to `::` or any IP.
* `DEBUG` - Set to `true` or `false`
* `ENV` - Set to `dev` or `prod`

## Deployment using systemd

An example systemd service file is included in the repository. A typical deployment:

```console
# adduser -m -d /home/prprocessor prprocessor
# sudo -u prprocessor -i
$ git clone https://github.com/theforeman/prprocessor -b app
$ python3 -m venv venv
$ . venv/bin/activate
$ pip install -e prprocessor
$ exit
# cp /home/prprocessor/prprocessor/prprocessor.service /etc/systemd/system/
# systemctl edit prprocessor.service
# systemctl enable --now prprocessor.service
```
