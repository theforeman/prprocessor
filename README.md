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

## Deployment using OpenShift

* Create the app
  * Click `Add` in the menu
  * Choose `From Git`
  * Enter Git Repo URL (https://github.com/theforeman/prprocessor)
  * Change the Builder Image version to `3.9-ubi9`
  * Expand Deployment
    * Add `ENV` with the value `prod`
  * Click `Create`
* Create the secret
  * Create a new key/value secret (like `prprocessor-prod-credentials`)
  * Add the 5 env vars (`GITHUB_APP_IDENTIFIER`, `GITHUB_PRIVATE_KEY`, `GITHUB_WEBHOOK_SECRET`, `REDMINE_URL`, `REDMINE_KEY`) and their values
  * Click `Add Secret to workload` on the secret's detail page
* Set up the webhook
  * Go to Builds and open the app's detail page
  * Under `Webhooks`, copy the GitHub URL with secret
  * Go to https://github.com/theforeman/prprocessor/settings/hooks and click `Add webhook`
  * Paste the URL in `Payload URL`
  * Change content type to `application/json`
  * Leave secret empty (the OpenShift secret is NOT the GitHub webhook secret)
  * Click `Add webhook`

On the Topology under Routes is the production URL. Use that to configure the GitHub application.

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
