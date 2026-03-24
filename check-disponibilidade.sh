url="http://bia-alb-1697404785.us-east-1.elb.amazonaws.com"
docker build -t check_disponibilidade -f Dockerfile_checkdisponibilidade .
docker run --rm -ti -e URL=$url check_disponibilidade
