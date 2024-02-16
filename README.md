# Dockerized-Laravel
A generic project structure to dockerize Laravel application for production environments

## Production
- You can choose to serve the application using Laravel Octane or FPM
- Either way you should use a web server like Nginx or Caddy to serve the application as a reverse proxy
- If you choose to use fpm, a socket will be created at path specified in fpm.conf
- If you choose to use octane, a socket will be created at path specified in octane.conf

## Warning
- This assumes a user with uid 1001 exists on the system and is named "sail" and is within the "docker" group
    - ```shell
      sudo usermod -aG docker sail
      ```
- Be careful with permissions
  - You should set facl like this
    - ```shell
      setfacl -R -m default:u:sail:rwx,default:g:docker:rwx,default:o:--- www
      ```