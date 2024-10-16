# use jupyter/datascience-notebook:2024-02-13 x86_64-2023-10-20

FROM ubuntu:22.04

LABEL desc="UB Slurm simulator Lite"

USER root

# install build and run essential
RUN apt update && \
    apt install -y build-essential git sudo vim zstd libzstd-dev && \
    apt install -y munge libmunge-dev libhdf5-dev \
        libjwt-dev libyaml-dev libdbus-1-dev \
        libmariadb-dev mariadb-server mariadb-client && \
    apt install -y libssl-dev openssh-server openssh-client libssh-dev

# # rename user:group to slurm:slurm
ARG SLURM_USER="slurm"
ARG SLURM_GROUP="slurm"
ARG SLURM_GID="1000"

ENV SLURM_USER="${SLURM_USER}" \
    SLURM_GROUP="${SLURM_GROUP}" \
    SLURM_GID=${SLURM_GID}

RUN useradd -m -s /bin/bash ${SLURM_USER} && \
    usermod -g ${SLURM_GROUP} ${SLURM_USER} && \
    usermod -a -G users ${SLURM_USER} && \
    usermod -a -G sudo ${SLURM_USER} &&  \
    echo "${SLURM_USER} ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers && \
    echo "${SLURM_USER}:slurm" |chpasswd && \
    chown -R ${SLURM_USER}:${SLURM_GROUP} /opt

ENV HOME="/home/${SLURM_USER}"

# copy daemons starters
COPY ./docker/slurm_sim/cmd_start ./docker/slurm_sim/cmd_stop /usr/local/sbin/
# COPY ./docker/virtual_cluster/vctools /opt/cluster/vctools

# directories
RUN mkdir /scratch && chmod 777 /scratch && \
    mkdir /scratch/jobs && chmod 777 /scratch/jobs

# configure sshd
RUN mkdir /var/run/sshd && \
    echo 'root:root' |chpasswd && \
    echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config

# setup munge,
RUN echo "secret munge key secret munge key secret munge key" >/etc/munge/munge.key &&\
    mkdir /run/munge  &&\
    chown -R slurm:slurm /var/log/munge /run/munge /var/lib/munge /etc/munge &&\
    chmod 600 /etc/munge/munge.key &&\
    su slurm -c "cmd_start munged" &&\
    munge -n | unmunge &&\
    su slurm -c "cmd_stop munged"

#configure mysqld
RUN cmd_start mysqld && \
    mysql -e 'DROP DATABASE IF EXISTS test;' && \
    mysql -e "CREATE USER 'slurm'@'%' IDENTIFIED BY 'slurm';" && \
    mysql -e 'GRANT ALL PRIVILEGES ON *.* TO "slurm"@"%" WITH GRANT OPTION;' && \
    mysql -e "CREATE USER 'slurm'@'localhost' IDENTIFIED BY 'slurm';" && \
    mysql -e 'GRANT ALL PRIVILEGES ON *.* TO "slurm"@"localhost" WITH GRANT OPTION;' && \
    cmd_stop mysqld

# set Slurm permissions, largely not needed for slurm sim
RUN mkdir /var/log/slurm  && \
    chown -R slurm:slurm /var/log/slurm  && \
    mkdir /install_files  && \
    chown -R slurm:slurm /install_files  && \
    mkdir /var/state  && \
    chown -R slurm:slurm /var/state  && \
    mkdir -p /var/spool/slurmd  && \
    chown -R slurm:slurm /var/spool/slurmd && \
    touch /bin/mail  && chmod 755 /bin/mail

#CMD ["/init"]

USER ${SLURM_USER}
WORKDIR "${HOME}"

COPY --chown=${SLURM_USER}:${SLURM_GROUP} . /opt/slurm_sim_tools

COPY --chown=${SLURM_USER}:${SLURM_GROUP} ./docker/slurm_sim_lite/startup_file.sh /install_files

RUN chmod +x /install_files/startup_file.sh
#COPY ./initial_test.sh /install_files


# build optimized version of SLURM SIM
RUN mkdir -p /opt/slurm_sim_bld/slurm_sim_opt && \
    cd /opt/slurm_sim_bld/slurm_sim_opt && \
    /opt/slurm_sim_tools/slurm_simulator/configure --prefix=/opt/slurm_sim \
        --disable-x11 --enable-front-end \
        --with-hdf5=no \
        CFLAGS='-O3 -Wno-error=unused-variable -Wno-error=implicit-function-declaration' \
        --enable-simulator && \
    make -j 8 && \
    make -j 8 install && \
    mkdir -p /opt/slurm_sim_bld/slurm_sim_deb && \
    cd /opt/slurm_sim_bld/slurm_sim_deb && \
    /opt/slurm_sim_tools/slurm_simulator/configure --prefix=/opt/slurm_sim_deb \
        --disable-x11 --enable-front-end \
        --enable-developer --disable-optimizations --enable-debug \
        --with-hdf5=no \
       'CFLAGS=-g -O0 -Wno-error=unused-variable -Wno-error=implicit-function-declaration' \
       --enable-simulator && \
    make -j 8 && \
    make -j 8 install

ENV PATH="/opt/slurm_sim_tools/bin:$PATH" \
    PYTHONPATH="/opt/slurm_sim_tools/src"  
    # do we need  :$PYHTONPATH here?

# timezone is set to America/New_York change to your zone, tzdata is dependency of jupyterlab
RUN sudo ln -fs /usr/share/zoneinfo/Europe/London /etc/localtime && \
   echo "Europe/London" | sudo tee /etc/timezone && \
   sudo DEBIAN_FRONTEND=noninteractive apt-get -y install tzdata

# python
ARG DEBIAN_FRONTEND=noninteractive
RUN  sudo apt install -y python3-pandas \
    python3-pip python3-arrow cython3 python3-pymysql python3-pytest python3-pytest-datadir \
    python3-venv python3-psutil python3-tqdm

USER ${SLURM_USER}

CMD ["/install_files/startup_file.sh"]

