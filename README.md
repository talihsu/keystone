# keystone
OpenStack Keystone

1. Build docker image with Dockerfile

2. Make sure run container with the following parameters
      - Expose port 5000 and 35357
      - Assign hostname to "keystone"

            docker run -itd -p 5000:5000 -p 35357:35357 --hostname keystone --name keystone image_name:tag

3. Check docker logs to make sure bootstrap finishes after running container
