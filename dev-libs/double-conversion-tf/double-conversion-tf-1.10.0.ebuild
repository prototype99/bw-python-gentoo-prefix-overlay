# Copyright 1999-2018 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2

EAPI=6

inherit cmake-utils multibuild

DESCRIPTION="Binary-decimal and decimal-binary conversion routines for IEEE doubles"
HOMEPAGE="https://github.com/google/double-conversion"
GIT_TAG="3992066a95b823efc8ccc1baf82a1cfc73f6e9b8"
SRC_URI="https://github.com/google/double-conversion/archive/${GIT_TAG}.tar.gz -> ${P}.tar.gz"

LICENSE="BSD"
SLOT="0/1"
KEYWORDS="~amd64 ~arm ~arm64 ~hppa ~mips ~ppc ~ppc64 ~sparc ~x86 ~amd64-fbsd ~amd64-linux ~x86-linux"
IUSE="+static-libs test"

pkg_setup() {
	MULTIBUILD_VARIANTS=( shared $(usev static-libs) )
}

src_prepare() {
	cmake-utils_src_prepare
	git init .
	git add .
	eapply "${FILESDIR}"/${PN}-1.10.0-tfslot.cmake
	ln -s double-conversion double-conversion-tf || die "Failed creating header symlink"
}

S="${WORKDIR}"/double-conversion-${GIT_TAG}

src_configure() {
	myconfigure() {
		local mycmakeargs=( -DBUILD_TESTING=$(usex test) )
		if [[ ${MULTIBUILD_VARIANT} = shared ]]; then
			mycmakeargs+=( -DBUILD_SHARED_LIBS=ON )
		fi
		if [[ ${MULTIBUILD_VARIANT} = static-libs ]]; then
			mycmakeargs+=( -DBUILD_SHARED_LIBS=OFF )
		fi

		cmake-utils_src_configure
	}

	multibuild_foreach_variant myconfigure
}

src_compile() {
	multibuild_foreach_variant cmake-utils_src_compile
}

src_test() {
	[[ ${MULTIBUILD_VARIANT} = shared ]] && cmake-utils_src_test
}

src_install() {
	myinstall() {
		[[ ${MULTIBUILD_VARIANT} = shared ]] && cmake-utils_src_install
		[[ ${MULTIBUILD_VARIANT} = static-libs ]] && \
			dolib ${BUILD_DIR}/libdouble-conversion-tf.a
	}

	multibuild_foreach_variant myinstall
}
