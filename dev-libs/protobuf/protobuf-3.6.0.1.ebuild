# Copyright 1999-2016 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# $Id$

EAPI=6

PYTHON_COMPAT=( python2_7 python3_{4,5,6} )
inherit cmake-utils elisp-common flag-o-matic python-r1 toolchain-funcs multilib-minimal

# If you bump this package, also consider bumping the official language bindings!
# At the current time these are java and python.
MY_PV=${PV/_beta/-beta-}
MY_PV=${MY_PV/_p/.}

DESCRIPTION="Google's Protocol Buffers -- an efficient method of encoding structured data"
HOMEPAGE="https://github.com/google/protobuf/ https://developers.google.com/protocol-buffers/"
SRC_URI="https://github.com/google/protobuf/archive/v${MY_PV}.tar.gz -> ${P}.tar.gz"

LICENSE="Apache-2.0"
SLOT="0/11"
KEYWORDS="~alpha ~amd64 ~arm ~arm64 ~hppa ~ia64 ~mips ~ppc ~ppc64 ~sh ~sparc ~x86 ~amd64-linux ~arm-linux ~x86-linux ~x64-macos ~x86-macos"
IUSE="emacs examples java python static-libs test vim-syntax zlib"

REQUIRED_USE="python? ( ${PYTHON_REQUIRED_USE} )"

CMAKE_USE_DIR="${S}"/cmake/

DEPEND="
        emacs? ( virtual/emacs )
        zlib? ( >=sys-libs/zlib-1.2.8-r1[${MULTILIB_USEDEP}] )
        test? ( dev-cpp/gmock[${MULTILIB_USEDEP}] )"

# This is provided for backwards compatibility due to (likely incorrect) use in consumers.
PDEPEND="
        java? ( dev-java/protobuf-java )
        python? ( dev-python/protobuf-python[${PYTHON_USEDEP}] )"

DOCS=( CHANGES.txt CONTRIBUTORS.txt README.md )

PATCHES=(
	"${FILESDIR}/${PN}-3.6.0-disable_no-warning-test.patch"
	"${FILESDIR}/${PN}-3.6.0-system_libraries.patch"
	"${FILESDIR}/${PN}-3.6.0-protoc_input_output_files.patch"
)

S="${WORKDIR}/${PN}-${MY_PV}"
src_prepare() {
        append-cppflags -DGOOGLE_PROTOBUF_NO_RTTI
        default
}

multilib_src_configure() {
	local mycmakeargs=( 
		-Dprotobuf_MODULE_COMPATIBLE=ON
		-DBUILD_SHARED_LIBS=ON
		-Dprotobuf_BUILD_TESTS=OFF
	)
	cmake-utils_src_configure
}

multilib_src_compile() {
        if tc-is-cross-compiler; then
                emake -C "${WORKDIR}"/build/src protoc
        fi

        default

        if use emacs; then
                elisp-compile "${S}"/editors/protobuf-mode.el
        fi
}

multilib_src_install_all() {
        if use vim-syntax; then
                insinto /usr/share/vim/vimfiles/syntax
                doins editors/proto.vim
                insinto /usr/share/vim/vimfiles/ftdetect/
                doins "${FILESDIR}/proto.vim"
        fi

        if use emacs; then
                elisp-install "${PN}" editors/protobuf-mode.el*
                elisp-site-file-install "${FILESDIR}/70${PN}-gentoo.el"
        fi

        if use examples; then
                DOCS+=( examples )
                docompress -x /usr/share/doc/"${PF}"/examples
        fi

        einstalldocs
}

pkg_postinst() {
        use emacs && elisp-site-regen
}

pkg_postrm() {
        use emacs && elisp-site-regen
}
