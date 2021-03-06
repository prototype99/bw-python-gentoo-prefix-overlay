#!/bin/bash

trap 'exit 1' TERM KILL INT QUIT ABRT

if [ "$#" -ne 1 ]; then
	echo "Usage: $0 EPREFIX"
	exit 1
fi

module switch PrgEnv-cray PrgEnv-gnu
module load cblas
module unload xalt
module load cmake
module load cray-hdf5-parallel
module load cray-netcdf-hdf5parallel
module load cray-tpsl
#module load cudatoolkit
module load boost

export EPREFIX="$1"
export HOST_PATH="$PATH"
export CRAY_CFLAGS="$(cc --cray-print-opts=cflags)"
export CRAY_LDFLAGS="$(cc --cray-print-opts=libs)"
export CRAY_PKG_CONFIG_PATH="$(cc --cray-print-opts=pkg_config_path)"
LD_LIB_PATHS="$(echo $LD_LIBRARY_PATH | tr ':' '\n')"

export PATH="$EPREFIX/sbin:$EPREFIX/usr/sbin:$EPREFIX/usr/bin:$EPREFIX/bin:$EPREFIX/tmp/usr/bin:$EPREFIX/tmp/bin:$PATH"
export LD_LIBRARY_PATH_BAK="$LD_LIBRARY_PATH"
export DYLD_LIBRARY_PATH_BAK="$DYLD_LIBRARY_PATH"
unset LD_LIBRARY_PATH
unset DYLD_LIBRARY_PATH
set PKG_CONFIG_PATH_BAK="$PKG_CONFIG_PATH"
unset PKG_CONFIG_PATH

CRAY_LIBRARY_PATHS="$LD_LIB_PATHS\n$(echo $CRAY_LDFLAGS | grep -Po '(?<=-L)([\S]*)')"
if [[ $(echo "$CRAY_LIBRARY_PATHS" | wc -l) > 0 ]]
then
	while read -r path; do
		CRAY_LDFLAGS="$CRAY_LDFLAGS -Wl,--rpath=$path" #,--enable-new-dtags"
	done <<< "$CRAY_LIBRARY_PATHS"
fi
if [[ $(echo "$LD_LIB_PATHS" | wc -l) > 0 ]]
then
	while read -r path; do
		LDP_LDFLAGS="$LDP_LDFLAGS -Wl,--rpath=$path" #,--enable-new-dtags"
	done <<< "$LD_LIB_PATHS"
fi
export CRAY_LDFLAGS="$CRAY_LDFLAGS $CRAY_BOOST_POST_LINK_OPTS"
export LDP_LDFLAGS="$LDP_LDFLAGS $CRAY_BOOST_POST_LINK_OPTS"
export PATH="$PATH:$HOST_PATH"

#Download bootstrap script and set stage1 configs on the first run
if [ ! -f "$EPREFIX/.stage1_config_set" ]; then
	wget http://rsync.prefix.bitzolder.nl/scripts/bootstrap-prefix.sh
	chmod +x bootstrap-prefix.sh

	#Ignore the big provided packages for the stage1 bootstrap
	mkdir -p $EPREFIX/tmp/etc/portage/profile
	echo "sys-devel/gcc-4.7.3" >> $EPREFIX/tmp/etc/portage/profile/package.provided
	echo "sys-devel/binutils-2.24" >> $EPREFIX/tmp/etc/portage/profile/package.provided
	touch "$EPREFIX/.stage1_config_set"
else
	echo "Stage 1 config already set. Skipping."
fi

#Bootstrap stage 1
if [ ! -f "$EPREFIX/.stage1_built" ]; then
	./bootstrap-prefix.sh $EPREFIX stage1 || exit 1
	touch "$EPREFIX/.stage1_built"
else
	echo "Stage 1 already built. Skipping."
fi

#Fetch the latest portage tree, rather than a snapshot
export LATEST_TREE_YES=1

#Always make sure that build directories (still) exit
mkdir -p /dev/shm/$USER/build{1,2}
ln -snf /dev/shm/$USER/build1 $EPREFIX/tmp/var/tmp/portage
ln -snf /dev/shm/$USER/build2 $EPREFIX/var/tmp/portage

#Set stage2/3 configs on the first run
if [ ! -f "$EPREFIX/.stage2_config_set" ]; then
	git clone https://github.com/camaclean/bw-python-gentoo-prefix-overlay.git $EPREFIX/usr/local/bw-python-gentoo-prefix-overlay
	sed -i '1iMARCH="bdver1"' $EPREFIX/etc/portage/make.conf
	sed -i 's|^CFLAGS=".*"|CFLAGS="\$\{CFLAGS\} -O2 -pipe -march=\$MARCH -I$EPREFIX/usr/include -I/usr/include -L$EPREFIX/lib -L$EPREFIX/usr/lib -L/lib64 -L/usr/lib64"|' $EPREFIX/etc/portage/make.conf
	sed -i 's|^USE=".*"|USE="unicode nls jpeg jpeg2k lcms tiff truetype lapack -e2fsprogs lzo lzma python mpi threads hdf hdf5 sqlite tk ncurses"|' $EPREFIX/etc/portage/make.conf
	sed -i 's|^MAKEOPTS=".*"|MAKEOPTS="-j9"|' $EPREFIX/etc/portage/make.conf
	sed -i 's|^MAKEOPTS=".*"|MAKEOPTS="-j9"|' $EPREFIX/tmp/etc/portage/make.conf
	echo 'LDFLAGS="${LDFLAGS} -Wl,--rpath=$EPREFIX/lib -Wl,--rpath=$EPREFIX/usr/lib -Wl,--enable-new-dtags"' >> $EPREFIX/etc/portage/make.conf
	echo 'FFLAGS="${CFLAGS}"' >> $EPREFIX/etc/portage/make.conf
	mkdir -p $EPREFIX/etc/portage/repos.conf
	echo '[BWGentooPrefix]' >> $EPREFIX/etc/portage/repos.conf/bwgp.conf
	echo "location = $EPREFIX/usr/local/bw-python-gentoo-prefix-overlay" >> $EPREFIX/etc/portage/repos.conf/bwgp.conf
	echo 'masters = gentoo' >> $EPREFIX/etc/portage/repos.conf/bwgp.conf
	echo 'sync-type = git' >> $EPREFIX/etc/portage/repos.conf/bwgp.conf
	echo 'sync-uri = https://github.com/camaclean/bw-python-gentoo-prefix-overlay.git' >> $EPREFIX/etc/portage/repos.conf/bwgp.conf
	echo 'auto-sync = yes' >> $EPREFIX/etc/portage/repos.conf/bwgp.conf
	ln -snf $EPREFIX/usr/local/bw-python-gentoo-prefix-overlay/profiles/prefix/linux/amd64-bw $EPREFIX/tmp/etc/portage/make.profile
	ln -snf $EPREFIX/usr/local/bw-python-gentoo-prefix-overlay/profiles/prefix/linux/amd64-bw $EPREFIX/etc/portage/make.profile
	#cp -r $EPREFIX/usr/local/bw-python-gentoo-prefix-overlay/profiles/prefix/linux/amd64-bw/env $EPREFIX/etc/portage/
	#cp $EPREFIX/usr/local/bw-python-gentoo-prefix-overlay/profiles/prefix/linux/amd64-bw/package.env $EPREFIX/etc/portage/
	touch "$EPREFIX/.stage2_config_set"
else
	echo "Stage 2 config already set. Updating overlay."
	cd $EPREFIX/usr/local/bw-python-gentoo-prefix-overlay/
	git pull
	cd -
fi
if [ ! -f "$EPREFIX/.stage2_built" ]; then
	./bootstrap-prefix.sh $EPREFIX stage2 || exit 1
	touch "$EPREFIX/.stage2_built"
else
	echo "Stage 2 already built. Skipping."
fi

#if [ ! -f "$EPREFIX/.stage3_config_set" ]; then
#	echo 'export PATH="$PATH:$HOST_PATH"' >> $EPREFIX/etc/profile
#	echo "export PKG_CONFIG_PATH=\"$EPREFIX/usr/lib/pkgconfig:\$PKG_CONFIG_PATH:/usr/lib64/pkgconfig\"" >> $EPREFIX/etc/profile
#	echo 'export PKG_CONFIG_PATH="$PKG_CONFIG_PATH:$CRAY_PKG_CONFIG_PATH"' >> $EPREFIX/etc/profile
#	sed -i -e "s|:/usr/bin:/bin||" -e "s|:/usr/sbin:/sbin||" $EPREFIX/etc/profile
#	touch "$EPREFIX/.stage3_config_set"
#	#ln -snf /usr/bin/perl $EPREFIX/usr/bin/perl
#fi

if [ ! -f "$EPREFIX/.stage3_built" ]; then
	./bootstrap-prefix.sh $EPREFIX stage3 || exit 1
	touch "$EPREFIX/.stage3_built"
else
	echo "Stage 3 already built. Skipping."
fi

if [ ! -f "$EPREFIX/.stage3_config_set" ]; then
	echo 'export PATH="$PATH:$HOST_PATH"' >> $EPREFIX/etc/profile
	echo "export PKG_CONFIG_PATH=\"$EPREFIX/usr/lib/pkgconfig:\$PKG_CONFIG_PATH:/usr/lib64/pkgconfig\"" >> $EPREFIX/etc/profile
	echo 'export PKG_CONFIG_PATH="$PKG_CONFIG_PATH:$CRAY_PKG_CONFIG_PATH"' >> $EPREFIX/etc/profile
	sed -i -e "s|:/usr/bin:/bin||" -e "s|:/usr/sbin:/sbin||" $EPREFIX/etc/profile
	touch "$EPREFIX/.stage3_config_set"
	#ln -snf /usr/bin/perl $EPREFIX/usr/bin/perl
fi

cat > $EPREFIX/setup-env.sh <<EOT
module switch PrgEnv-cray PrgEnv-gnu
module unload xalt
module load cray-hdf5
module load cray-netcdf
module load cray-tpsl

export EPREFIX="$EPREFIX"
export HOST_PATH="\$PATH"
export CRAY_CFLAGS="\$(cc --cray-print-opts=cflags)"
export CRAY_CFLAGS="\$CRAY_CFLAGS \$CRAY_BOOST_INCLUDE_OPTS"
export CRAY_LDFLAGS="\$(cc --cray-print-opts=libs)"
export CRAY_PKG_CONFIG_PATH="\$(cc --cray-print-opts=pkg_config_path)"
LD_LIB_PATHS="\$(echo \$LD_LIBRARY_PATH | tr ':' '\n')"

export PATH="\$EPREFIX/usr/bin:\$EPREFIX/bin:\$EPREFIX/tmp/usr/bin:\$EPREFIX/tmp/bin:\$PATH"
export PKG_CONFIG_PATH_BAK="\$EPREFIX/usr/lib/pkgconfig:\$PKG_CONFIG_PATH:/usr/lib64/pkgconfig"

CRAY_LIBRARY_PATHS="\$LD_LIB_PATHS
\$(echo \$CRAY_LDFLAGS | grep -Po '(?<=-L)([\S]*)')"
if [[ \$(echo "\$CRAY_LIBRARY_PATHS" | wc -l) > 0 ]]
then
	while read -r path; do
		CRAY_LDFLAGS="\$CRAY_LDFLAGS -Wl,--rpath=\$path" #,--enable-new-dtags"
	done <<< "\$CRAY_LIBRARY_PATHS"
fi
if [[ \$(echo "\$LD_LIB_PATHS" | wc -l) > 0 ]]
then
	while read -r path; do
		LDP_LDFLAGS="\$LDP_LDFLAGS -Wl,--rpath=\$path" #,--enable-new-dtags"
	done <<< "\$LD_LIB_PATHS"
fi
export CRAY_LDFLAGS="\$CRAY_LDFLAGS \$CRAY_BOOST_POST_LINK_OPTS"
export LDP_LDFLAGS="\$LDP_LDFLAGS \$CRAY_BOOST_POST_LINK_OPTS"
export PATH="\$PATH:\$HOST_PATH"
export PKG_CONFIG_PATH="\$EPREFIX/usr/lib/pkgconfig:\$PKG_CONFIG_PATH:\$CRAY_PKG_CONFIG_PATH:/usr/lib64/pkgconfig"
EOT
chmod +x $EPREFIX/setup-env.sh

export PKG_CONFIG_PATH="$EPREFIX/usr/lib/pkgconfig:$PKG_CONFIG_PATH:$CRAY_PKG_CONFIG_PATH:/usr/lib64/pkgconfig"
export LD_LIBRARY_PATH="$LD_LIBRARY_PATH_BAK"
export DYLD_LIBRARY_PATH="$DYLD_LIBRARY_PATH_BAK"

if [ ! -f "$EPREFIX/.rebuilt" ]; then
	if [ ! -f "$EPREFIX/.start_rebuild" ]; then
		touch "$EPREFIX/.start_rebuild"
		echo "Starting world rebuild"
		emerge -ve world || exit 1
		rm "$EPREFIX/.start_rebuild"
	else
		echo "Resuming world rebuild"
		emerge -v --resume || exit 1
		rm "$EPREFIX/.start_rebuild"
	fi
	touch "$EPREFIX/.rebuilt"
fi

emerge -uvDN gentoolkit eix pillow native-mpi mpi4py libsci numpy matplotlib pycuda h5py netcdf4-python pandas statsmodels expose-python
eselect python set 1
USE="-smp" emerge -v ipython
emerge -v ipython
