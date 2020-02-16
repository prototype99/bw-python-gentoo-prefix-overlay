# Copyright 1999-2018 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2

EAPI=6

FORTRAN_NEEDED="test"

inherit cmake-utils cuda fortran-2 toolchain-funcs

DESCRIPTION="C++ template library for linear algebra"
HOMEPAGE="http://eigen.tuxfamily.org/"
SRC_URI="https://bitbucket.org/eigen/eigen/get/429aa5254200.tar.gz -> eigen-429aa5254200.tar.gz"

LICENSE="MPL-2.0"
SLOT="3"
KEYWORDS="~alpha ~amd64 ~arm ~arm64 ~ia64 ~ppc ~ppc64 ~sparc ~x86 ~amd64-linux ~x86-linux"
IUSE="altivec c++11 cuda debug doc neon openmp test" #zvector vsx
RESTRICT="!test? ( test )"

RDEPEND="!dev-cpp/eigen:0"
DEPEND="
	doc? ( app-doc/doxygen[dot,latex] )
	test? (
		dev-libs/gmp:0
		dev-libs/mpfr:0
		media-libs/freeglut
		media-libs/glew
		sci-libs/adolc[sparse]
		sci-libs/cholmod
		sci-libs/fftw:3.0
		sci-libs/pastix
		sci-libs/umfpack
		sci-libs/scotch
		sci-libs/spqr
		sci-libs/superlu
		virtual/opengl
		virtual/pkgconfig
		cuda? ( dev-util/nvidia-cuda-toolkit )
	)
"
# Missing:
# METIS-5
# GOOGLEHASH

src_unpack() {
	default
	mv eigen* ${P} || die
}

src_prepare() {
	sed -e 's:-g2::g' \
		-i cmake/EigenConfigureTesting.cmake || die

	sed -e "/add_subdirectory(demos/d" \
		-i CMakeLists.txt || die

	if ! use test; then
		sed -e "/add_subdirectory(test/d" \
			-i CMakeLists.txt || die

		sed -e "/add_subdirectory(blas/d" \
			-e "/add_subdirectory(lapack/d" \
			-i CMakeLists.txt || die
	fi
	sed -e "/Unknown build type/d" \
		-i CMakeLists.txt || die

	eapply "${FILESDIR}"/${P}.patch
	local gcc_version=$(gcc-version)
	[ $gcc_version == 4.9 ] && eapply "${FILESDIR}"/${P}-gcc-4.9.patch

	use cuda && cuda_src_prepare
	cmake-utils_src_prepare
}

src_configure() {
	local mycmakeargs=(
		-DCMAKEPACKAGE_INSTALL_DIR="${EPREFIX}"/usr/share/eigen3tensorflow/cmake
		-DINCLUDE_INSTALL_DIR:STRING="include/eigen3-tensorflow"
		#-DINCLUDE_INSTALL_DIR="${EPREFIX}"/usr/include/eigen3-tensorflow
	)
	cmake-utils_src_configure
}


src_test() {
	local mycmakeargs=(
		-DEIGEN_TEST_NOQT=ON
		-DEIGEN_TEST_ALTIVEC="$(usex altivec)"
		-DEIGEN_TEST_CXX11="$(usex c++11)"
		-DEIGEN_TEST_CUDA="$(usex cuda)"
		-DEIGEN_TEST_OPENMP="$(usex openmp)"
		-DEIGEN_TEST_NEON64="$(usex neon)"
	)
	cmake-utils_src_configure
	cmake-utils_src_compile blas
	cmake-utils_src_compile buildtests
	cmake-utils_src_test
}
