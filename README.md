# Magic Git Deploy
## Description
Magic Git Deploy is a script which automatically deploys the latest build from from a local Git repository to a deployment directory on a remote server. It is run in a crontab every minute, and spots when you push a fresh revision up to the repository, automatically deploying it.

It does so by checking the repository's hash, and comparing it with the previous hash. If the hash differs, it checks out the repository to a temporary directory, and then uses rsync to deploy it to the deployment directory.

Doing so saves the need to manually copy over a project to the server when it's ready to deploy. Instead, you can simply push your git repository up to the server, and have it taken care of automatically, and encourages frequent deployments.

So, in a nutshell, you do this on your local machine:

```shell
git push deploy master
```

And the latest revision of your project is live within moments!

## Setup and Usage
Initial setup can take a little work for each of your projects, but once done you’ll be saving yourself a lot of time.

Let’s imagine we’ve got a website you want to frequently deploy updates to. You’re developing it locally, but periodically you copy it over to the main server and overwrite what’s currently there so you can take your iteration live.

### Part 1: Create Your Deployment Git Repository
On the **server**, create a dedicated remote repository for deployment:

```shell
mkdir ~/git/my_website_deployment.git
cd ~/git/my_website_deployment.git
git init --bare
```
Note that you should assume that whenever you push your git repo here, it will end up live!

In your project’s directory (on your **local** machine), you should already have a local Git repository up and running. You may even have installed remote repositories.

You should now add the remote repository you created above on your **local** machine:

```shell
cd ~/my_website_dev
git remote add deploy username@server:~/git/my_website_deployment.git
```

Also, don't forget to create a directory on the **server** for the deployment itself!

```shell
mkdir /var/www/my_website
```

You may already have one, in which case you're good to go. (The deployment directory can have an existing deployment there, but note that it will be over-written the first time you push your local Git  repository, so make sure you've brought any ad-hoc changes back into your local repository)

### Part 2: Setup the Deployment Cron
1 Copy `magic_git_deploy` over to your deployment box, and ensure it’s somewhere in the system’s `PATH` variable.

2 Now, make a note of the following:

**Deployment Repository** (this is where you’ll be pushing your local Git repo to when you want to automate a deployment)

**Deployment Directory** (the actual directory where your deployment will reside)

**Logging Directory** (a directory to keep logs)

So, in our example website project, I’d have:

**Deployment Repository**: `~/git/my_website_deployment.git`

**Deployment Directory**: `/var/www/my_website`

**Logging Directory**: `~/logs`

3 Now, create your cron. Typical invocation at the command line is:

```shell
crontab -e
```

You will need to invoke `magic_git_deploy` as a cron supplying the deployment repo, the deployment directory and the logging directory as we spoke about above.

For the above example, your cron would look like this:

```shell
SHELL=/bin/bash
PATH=/usr/kerberos/bin:/usr/local/bin:/bin:/usr/bin:

#*     *     *   *    *        command to be executed
#-     -     -   -    -
#|     |     |   |    |
#|     |     |   |    +----- day of week (0 - 6) (Sunday=0)
#|     |     |   +------- month (1 - 12)
#|     |     +--------- day of month (1 - 31)
#|     +----------- hour (0 - 23)
#+------------- min (0 - 59)
* * * * * nice magic_git_deploy.sh --repo ~/git/my_website_deployment.git --deploy /var/www/my_website --log ~/logs
```

And that's it! You should now test the deployment by pushing your master branch from your local repo as follows:

```shell
git push deploy master
```

If you don't see your deployment go live, you should inspect the logs in the logging directory you supplied for problems, or drop me a message on GitHub.

### FAQ

Q. I've just pushed my repository for the first time, and it's taking a while for the changes to show up. Is this a bug?

A. The script uses ```rsync``` to make the deployment. On first deployment, `rsync` has to copy over each and every file to the deployment directory, whereas on subsequent pushes it only has to copy over the files that have changes. This can mean the first deployment takes longer.

Q. If I deleted a file from my Git repository, will this be reflected in the deployment?

A. Yes. The script executes `rsync` in a way that will remove any files which no longer exist. You should assume that any files in the deployment directory will be overwritten or deleted as required.

Q. Is there a way to be notified of a successful deployment without having to consult the logs?

A. At the moment there is only support for [Prowl](http://www.prowlapp.com).

Q. Can I use this script with multiple projects?

A. Yes, just give each project its own cron.

Q. I'd prefer to run this as a background job rather than via a cron. Is this possible?

A. Indeed! You can run the script like so:

```shell
nohup magic_git_deploy.sh --repo ~/git/my_website_deployment.git --deploy /var/www/my_website --log ~/logs --background --check_frequency 1 > /dev/null 2>&1
```
Where `--background` tells the script to keep running, and `--check_frequency` is the period in minutes where the script should check for an update.

You can also add this to your crontab in order to ensure the script runs in background mode after each restart:

```shell
@reboot nohup magic_git_deploy.sh --repo ~/git/my_website_deployment.git --deploy /var/www/my_website --log ~/logs --background --check_frequency 1
```

Q. Can I test out the script with the logging going to the main screen?

A. Yes, simply invoke the script with `'<<stdout>>'` as the log file. This will pipe all output to `/dev/stdout`.

Q. There are some files I want to completely ignore, so that they don't get overwritten or deleted by the deployment. Is there a way I can achieve this?

A. Yes, just create a file named `.deployignore` at the root of your project and add it to your git repository. Any files listed here will be completely ignored by the deployment process.

Q. Shouldn't I really be using Ansible to deploy stuff, perhaps with a Git hook to trigger the Ansible deployment?

A. Yes, you probably should ;) I wrote this tool before I discovered Ansible, and I'd advise you to look into using that instead these days.
