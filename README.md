# Dockerized-Laravel
A generic project structure to dockerize Laravel application for production environments

## Warning
- This assumes a user with uid 1001 exists on the system and is named "sail"
- Be careful with permissions
  - You should set facl like this
    - ```shell
      setfacl -R -m default:u:sail:rwx,default:g:docker:rwx,default:o:--- www
      ```
  - This is a sample nginx configuration to put inside /etc/nginx/sites-available/default
    ```nginx
    server {
    listen 80;
    server_name your_domain.com;  # Change this to your domain or IP address

    location / {
    proxy_pass http://127.0.0.1:8000;  # Change the port accordingly
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection 'upgrade';
    proxy_set_header Host $host;
    proxy_cache_bypass $http_upgrade;
    }

    # Additional configurations can be added as needed
    }
    ```