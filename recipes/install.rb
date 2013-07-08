## Cookbook Name:: deploy-drupal
## Recipe:: install
##
## make sure drupal is connected to database
##  1. drush si (if not connected and empty db)
##  2. load db from dump (if db empty)
##  3. run post-install script
##  4. fix file permissions
##  5. clear drush cache

   # assemble all necessary query strings and paths
# requires drush 6
DRUPAL_DISCONNECTED = [ "drush status",
                        "--fields=db-status",
                        "| grep Connected",
                        "| wc -l | xargs test 0 -eq"
                      ].join(' ')

DB_ROOT_CONNECTION  = [ "mysql",
                        "--user='root'",
                        "--host='localhost'",
                        "--password='#{node['mysql']['server_root_password']}'"
                      ].join(' ')

DB_FULL             = [ DB_ROOT_CONNECTION,
                        "--database=#{node['deploy-drupal']['db_name']}",
                        "-e \"SHOW TABLES;\"",
                        "| wc -l | xargs test 0 -ne"
                      ].join(' ')

DRUSH_DB_URL        = "mysql://" +
                          node['deploy-drupal']['mysql_user'] + ":'" +
                          node['deploy-drupal']['mysql_pass'] + "'@localhost/" +
                          node['deploy-drupal']['db_name']

# fixes sendmail error https://drupal.org/node/1826652#comment-6706102
DRUSH_SI            = [ "php -d sendmail_path=/bin/true",
                        "/usr/share/php/drush/drush.php",
                        "site-install standard -y",
                        "--account-name=#{node['deploy-drupal']['admin_user']}",
                        "--account-pass=#{node['deploy-drupal']['admin_pass']}",
                        "--db-url=#{DRUSH_DB_URL}",
                        "--site-name='#{node['deploy-drupal']['project_name']}'"
                      ].join(' ')

DEPLOY_PROJECT_DIR  = node['deploy-drupal']['deploy_dir']   + "/" +
                      node['deploy-drupal']['project_name']

DEPLOY_SITE_DIR     = DEPLOY_PROJECT_DIR   + "/" +
                      node['deploy-drupal']['drupal_root_dir']

# TODO must raise exception if db is full but Drupal is not connected
# install Drupal Site
execute "drush-site-install" do
  cwd DEPLOY_SITE_DIR
  command DRUSH_SI
  only_if DRUPAL_DISCONNECTED, :cwd => DEPLOY_SITE_DIR
  not_if DB_FULL, :cwd => "'#{DEPLOY_SITE_DIR}'"
  notifies :run, "execute[drush-cache-clear]", :delayed
  notifies :run, "execute[drush-suppress-http-status-error]", :delayed
  notifies :run, "execute[fix-drupal-permissions]", :delayed
end

# load the drupal database from specified local SQL file
# Using zless instead of cat/zcat to optionally support gzipped files 
# "`drush sql-connect`" because "drush sqlc" returns 0 even on connection failure
execute "load-drupal-db-from-sql" do
  cwd DEPLOY_SITE_DIR
  command "zless '#{node['deploy-drupal']['sql_load_file']}' | `drush sql-connect`"
  only_if  "test -f '#{node['deploy-drupal']['sql_load_file']}'", :cwd => DEPLOY_PROJECT_DIR
  not_if DB_FULL
  notifies :run, "execute[run-post-install-script]"
  notifies :run, "execute[drush-cache-clear]", :delayed
  notifies :run, "execute[drush-suppress-http-status-error]", :delayed
  notifies :run, "execute[fix-drupal-permissions]", :delayed
end

execute "run-post-install-script" do
  cwd DEPLOY_SITE_DIR
  command "bash '#{node['deploy-drupal']['post_install_script']}'"
  only_if "test -f '#{node['deploy-drupal']['post_install_script']}'", :cwd => DEPLOY_PROJECT_DIR
  action :nothing
end

# fix permissions of project root
execute "fix-drupal-permissions" do
  command "bash drupal-perm.sh"
  # TODO this should be action :nothing and only notified by
  # site-install, but that requires fixing ownership of deploy_dir
end

# TODO should only be used when Drupal is served through a forwarded port
execute "drush-suppress-http-status-error" do
  cwd DEPLOY_SITE_DIR
  command "drush vset -y drupal_http_request_fails FALSE"
  action :nothing
end

# drush cache clear
execute "drush-cache-clear" do
  cwd DEPLOY_SITE_DIR
  command "drush cache-clear all"
  action :nothing
end
