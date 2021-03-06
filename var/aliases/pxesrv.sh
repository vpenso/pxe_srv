PXESRV_ROOT=${PXESRV_ROOT:-$PXESRV_PATH/public}
PXESRV_PORT=${PXESRV_PORT:-4567}
PXESRV_LOG=/tmp/pxesrv.log
PXESRV_DOCKER_CONTAINER=pxesrv
PXESRV_VM_IMAGE=debian9
PXESRV_VM_INSTANCE=lxcm02
PXE_VM_INSTANCE=lxdev01

export PXESRV_ROOT \
       PXESRV_PORT \
       PXESRV_LOG \
       PXESRV_DOCKER_CONTAINER \
       PXESRV_VM_IMAGE \
       PXESRV_VM_INSTANCE


#
# Build and run a pxesrv docker service container instance
#
pxesrv-docker-container() {
        # build the container image
        docker build -t $PXESRV_DOCKER_CONTAINER $PXESRV_PATH
        # start the container instance
        docker run --detach \
                   --tty \
                   --interactive \
                   --name $PXESRV_DOCKER_CONTAINER \
                   --publish $PXESRV_PORT:$PXESRV_PORT \
                   --volume $PXESRV_ROOT:/srv/pxesrv \
                   --restart=always \
               $PXESRV_DOCKER_CONTAINER
}

#
# Celan up pxesrv docker containers
#
pxesrv-docker-container-remove() {
        docker container stop $PXESRV_DOCKER_CONTAINER
        docker container rm $PXESRV_DOCKER_CONTAINER
        docker image rm $PXESRV_DOCKER_CONTAINER
}

#
# Define and start a VM to host the pxesrv service
#
pxesrv-vm-sync-root() {
        echo "Copy $PXESRV_ROOT to $PXESRV_VM_INSTANCE:/srv/pxesrv"
        vm sync $PXESRV_VM_INSTANCE -r $PXESRV_ROOT/ :/srv/pxesrv |:

}

pxesrv-vm-instance() {
        # start the VM instance for the pxesrv server
        vm shadow $PXESRV_VM_IMAGE $PXESRV_VM_INSTANCE
        # install prerequisites
        case "$PXESRV_VM_IMAGE" in
                debian*)
                        vm exec $PXESRV_VM_INSTANCE -r '
                                apt update
                                apt -yq install git-core ruby-sinatra
                        '
                        ;;
                centos*)
                        vm exec $PXESRV_VM_INSTANCE -r -- \
                                yum install -yq epel-release
                        vm exec $PXESRV_VM_INSTANCE -r -- \
                                yum install -yq rubygem-sinatra
                        ;;
                *)
                        echo Install Ruby Sinatra!
                        ;;
        esac
        # rsync this repo into the VMs /opt
        vm sync $PXESRV_VM_INSTANCE -r $PXESRV_PATH :/opt |:
        # rsync PXESRV_ROOT into the VM /srv/pxesrv
        pxesrv-vm-sync-root
        # add the repo to the login environment
        vm exec $PXESRV_VM_INSTANCE -r \
                'echo "source /opt/pxesrv/source_me.sh" >> $HOME/.bashrc'
}

#
# Bootstrap a VM instance and start pxesrv in foreground
#
pxesrv-vm-instance-debug() {
       # bootstrap the service
       pxesrv-vm-instance
       # start the service in foreground
       vm exec $PXESRV_VM_INSTANCE -r -- \
               PXESRV_ROOT=/srv/pxesrv $PXESRV_PATH/pxesrv -p $PXESRV_PORT

}

#
# Boostrap a VM instance and start pxesrv with systemd 
#
pxesrv-vm-instance-systemd-unit() {
        # bootstrap the service
        pxesrv-vm-instance
        # use systemd to start the service
        vm exec $PXESRV_VM_INSTANCE -r '
                ln -s $PXESRV_PATH/pxesrv /usr/sbin/pxesrv
                # install the service unit file
                cp $PXESRV_PATH/var/systemd/pxesrv.service /etc/systemd/system/
                systemctl daemon-reload
                # link to the document root within this repo
                systemctl enable --now pxesrv
                systemctl status pxesrv
        '
}

#
# Boostrap a VM instance and start pxesrv in a docker container
#
pxesrv-vm-instance-docker-container() {
        # bootstrap the service
        pxesrv-vm-instance
        # start pxesrv in a docker container
        vm exec $PXESRV_VM_INSTANCE -r '
                # tools to use extra repository over HTTPS
                apt-get install -y apt-transport-https ca-certificates curl gnupg2 software-properties-common
                # add official Docker GPG keys
                curl -fsSL https://download.docker.com/linux/debian/gpg | apt-key add -
                # set up the stable repository
                add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/debian $(lsb_release -cs) stable"
                # install components
                apt-get update && apt-get -y install docker-ce
                # build and run the pxesrv service container
                pxesrv-docker-container
        '
}

#
# Start a VM instance with PXE boot enable and connect to VNC
#
pxe-vm-instance() {
        local instance=${1:-$PXE_VM_INSTANCE}
        # define and start a VM instance 
        vm shadow --net-boot \
                  --memory 2 \
                  $PXESRV_VM_IMAGE $instance
        # open VNC console
        echo Open VNC connection...
        vm view $instance &
}
