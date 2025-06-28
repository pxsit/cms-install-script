Contest Management System Installation Script
=============================================
**This is a convenience script that is used to install [CMS](http://cms-dev.github.io/) using the Python Virtual Environment (venv) method**

Basic Installation
------------------
1. Run the following command in the directory you want to install cms in
```bash
curl -LO https://raw.githubusercontent.com/pxsit/cms-install-script/refs/heads/main/cms-install.sh | bash
```
2. Follow the script instructions
3. Access at localhost:8888 localhost:8889 localhost:8890

Installation with Website Integration via Cloudflare
----------------------------------------------------
For ease of demonstration my websites name will be https://grader.cms.com, https://admin.cms.com, and https://leaderboard.cms.com
1. Make sure that your domain have an Active status on Cloudflare and that you have port 443,80 Forwarded
2. Go to DNS -> Records
3. Add 3 type A records with the name of each records being the name you want your subdomain to be and the IPV4 address be your server's IPV4 address and with Proxied status DNS only.
If you have finished you will have something that looked like this
![image](https://github.com/user-attachments/assets/488c98cb-9625-4aa4-a9da-c65b63d31a64)

4. Run the following command in the directory you want to install cms in
```bash
curl -LO https://raw.githubusercontent.com/pxsit/cms-install-script/refs/heads/main/cms-install.sh | bash
```
5. Follow the scripts instructions and when prompted to link you cms to a website answer Y
6. Enter the subdomain of each Service, mine will be grader.cms.com, admin.cms.com, and leaderboard.cms.com respectively
7. (Recommend) Add an SSL certificate using certbot
8. Once certbot have finished or you decided you don't want an SSL certificate change the Proxied status to Proxied.

Ranking Web Server (RWS) usage
------------------------------
If your CMS only have one contest, RWS will work normally without configuration
But if more than one contest is present, you need to configure RWS by editing resource-service.conf in your cms directory
by changing the contest id to the contest id you want to have the RWS linked to (beware, other contest will not become accessible)

The contest id will be shown when editing a contest in the admin tab as shown in the image

![image](https://github.com/user-attachments/assets/55967026-0c1d-474c-8c92-8e9c783c0b8a)

After confiuration, restart the cms services by runnning the following command
```bash
sudo systemctl restart cms-log
sudo systemctl restart cms
sudo systemctl restart cms-ranking
```
