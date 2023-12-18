# Dockerized-Laravel
A generic project structure to dockerize Laravel application for production environments

## Warning
- This assumes a user with uid 1001 exists on the system and is named "sail"
- Be careful with permissions
  - You should set facl like this
    - ```shell
      setfacl -R -m default:u:sail:rwx,default:g:docker:rwx,default:o:--- www
      ```