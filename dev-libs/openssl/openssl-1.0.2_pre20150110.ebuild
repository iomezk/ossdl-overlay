# Copyright 1999-2013 Gentoo Foundation
# Copyright 2013–2014 W. Mark Kubacki
# Distributed under the terms of the GNU General Public License v2

EAPI="4"

inherit eutils flag-o-matic toolchain-funcs multilib multilib-minimal

# MY_PV=1.0.2, MY_PRE=20131117, MY_P=openssl-1.0.2-stable-SNAP-20131117
# G_P is Gentoo's equivalent P, openssl-1.0.2
MY_PV="${PV%%_*}"
MY_PRE="${PV##*_pre}"
MY_PRE="${MY_PRE%%_*}"
MY_P="${PN}-${MY_PV}-stable-SNAP-${MY_PRE}"
G_P="${PN}-${MY_PV}"
S="${WORKDIR}/${MY_P}"

REV="1.7"
DESCRIPTION="full-strength general purpose cryptography library (including SSL and TLS)"
HOMEPAGE="http://www.openssl.org/"
SRC_URI="mirror://openssl-snapshots/${MY_P}.tar.gz
	http://cvs.pld-linux.org/cgi-bin/cvsweb.cgi/packages/${PN}/${PN}-c_rehash.sh?rev=${REV} -> ${PN}-c_rehash.sh.${REV}"

LICENSE="openssl"
SLOT="0"
KEYWORDS="amd64 ~arm ~x86 ~amd64-fbsd ~x86-fbsd ~arm-linux ~x86-linux"
IUSE="bindist +cryptodev +gmp kerberos rfc3779 smime sse2 static-libs test tls-heartbeat vanilla zlib"
IUSE="${IUSE} +dsa dtls jpake +psk srp srtp ssl2 ssl3"
IUSE="${IUSE} +camellia +des +rc4 rc5"
IUSE="${IUSE} +blowfish +cast gost idea md4 mdc2 rc2 seed"

REQUIRED_USE="cryptodev? ( dsa )
	ssl2? ( ssl3 )
	ssl3? ( des )
	srtp? ( dtls )
	dtls? ( srtp )
	smime? ( des md4 rc2 )"

# The blocks are temporary just to make sure people upgrade to a
# version that lack runtime version checking.  We'll drop them in
# the future.
RDEPEND="gmp? ( dev-libs/gmp[static-libs(+)?,${MULTILIB_USEDEP}] )
	zlib? ( sys-libs/zlib[static-libs(+)?,${MULTILIB_USEDEP}] )
	kerberos? ( app-crypt/mit-krb5 )
	abi_x86_32? (
		!<=app-emulation/emul-linux-x86-baselibs-20140508
		!app-emulation/emul-linux-x86-baselibs[-abi_x86_32(-)]
	)
	!<net-misc/openssh-5.9_p1-r4
	!<net-libs/neon-0.29.6-r1"
DEPEND="${RDEPEND}
	sys-apps/diffutils
	>=dev-lang/perl-5
	test? ( sys-devel/bc )"
PDEPEND="app-misc/ca-certificates"
# This is part of the kernel:
#	cryptodev? ( app-crypt/cryptodev-linux )

MULTILIB_WRAPPED_HEADERS=(
	usr/include/openssl/opensslconf.h
)

src_prepare() {
	if use bindist; then
		# We have to retain the USE flag bindist for OpenSSH.
		die "bindist has been removed from this ebuild."
	fi

	SSL_CNF_DIR="/etc/ssl"
	sed \
		-e "/^DIR=/s:=.*:=${EPREFIX}${SSL_CNF_DIR}:" \
		-e "s:SSL_CMD=/usr:SSL_CMD=${EPREFIX}/usr:" \
		"${DISTDIR}"/${PN}-c_rehash.sh.${REV} \
		> "${WORKDIR}"/c_rehash || die #416717

	# Make sure we only ever touch Makefile.org and avoid patching a file
	# that gets blown away anyways by the Configure script in src_configure
	rm -f Makefile

	if ! use vanilla ; then
		epatch "${FILESDIR}"/${PN}-1.0.0a-ldflags.patch #327421
		epatch "${FILESDIR}"/${PN}-1.0.0d-windres.patch #373743
		sed -i -e "s:OpenSSL-libssl:OpenSSL:" Makefile.org
		epatch "${FILESDIR}"/0001-Enable-parallel-builds-for-example-with-MAKEOPTS-j4.patch
		epatch "${FILESDIR}"/0001-Make-the-assembly-syntax-compatible-with-x32-gcc.patch
		for F in $(find -name '*.pod' -type d); do
			sed -i -E 's:=item ([0-9]+):=item C<\1>:' $F
		done
		epatch "${FILESDIR}"/${PN}-1.0.1e-s_client-verify.patch #472584
	fi

	if ! use des ; then
		epatch "${FILESDIR}"/0001-Fix-compilation-with-no-des.patch
	fi

	epatch  "${FILESDIR}"/0001-Add-RAND-engine-for-Linux-syscall-getrandom.patch \
		"${FILESDIR}"/0002-Add-syscall-number-for-getrandom-and-ARM64.patch \
		"${FILESDIR}"/0003-crypto-engine-eng_linux_getrandom.c-Do-not-register-.patch
	epatch	"${FILESDIR}"/0001-x86-_64-cpuid.pl-rdrand-to-fill-a-buffer.patch

	# raises minimum DH group size, from 'any' to '1024 bits or greater'
	epatch "${FILESDIR}"/0001-require-DH-group-of-1024-bits.patch

	# limits usage of RC4 to TLS 1.0 and older; from CloudFlare
	epatch "${FILESDIR}"/0001-Disable-RC4-for-TLS-v1.1-server-side.patch

	epatch "${FILESDIR}"/0001-Use-HIGH-ciphers-by-default.patch

	# disable fips in the build
	# make sure the man pages are suffixed #302165
	# don't bother building man pages if they're disabled
	sed -i \
		-e '/DIRS/s: fips : :g' \
		-e '/^MANSUFFIX/s:=.*:=ssl:' \
		-e '/^MAKEDEPPROG/s:=.*:=$(CC):' \
		-e $(has noman FEATURES \
			&& echo '/^install:/s:install_docs::' \
			|| echo '/^MANDIR=/s:=.*:='${EPREFIX}'/usr/share/man:') \
		Makefile.org \
		|| die
	# show the actual commands in the log
	sed -i '/^SET_X/s:=.*:=set -x:' Makefile.shared

	# allow openssl to be cross-compiled
	cp "${FILESDIR}"/gentoo.config-1.0.1 gentoo.config || die
	chmod a+rx gentoo.config

	append-flags -fno-strict-aliasing
	append-flags $(test-flags-CC -Wa,--noexecstack)
	append-cppflags -DOPENSSL_NO_BUF_FREELISTS

	if use cryptodev; then
		ewarn "If you have not compiled cryptodev into the kernel"
		ewarn "emerge app-crypt/cryptodev-linux before OpenSSL!"
		# sys-kernel/linux-headers doesn't contain crypto/cryptodev.h, therefore:
		append-flags -I/usr/src/linux
	fi

	if ! use vanilla; then
		epatch_user #332661
	fi

	sed -i '1s,^:$,#!'${EPREFIX}'/usr/bin/perl,' Configure #141906
	# The config script does stupid stuff to prompt the user.  Kill it.
	sed -i '/stty -icanon min 0 time 50; read waste/d' config || die
	#./config --test-sanity || die "I AM NOT SANE"

	multilib_copy_sources
}

multilib_src_configure() {
	unset APPS #197996
	unset SCRIPTS #312551
	unset CROSS_COMPILE #311473

	tc-export CC AR RANLIB RC

	# Clean out patent-or-otherwise-encumbered code
	# Camellia: Royalty Free            http://en.wikipedia.org/wiki/Camellia_(cipher)
	# IDEA:     Expired                 http://en.wikipedia.org/wiki/International_Data_Encryption_Algorithm
	# EC:       ????????? ??/??/2015    http://en.wikipedia.org/wiki/Elliptic_Curve_Cryptography
	# MDC2:     Expired                 http://en.wikipedia.org/wiki/MDC-2
	# RC5:      5,724,428 03/03/2015    http://en.wikipedia.org/wiki/RC5

	use_ssl() { usex $1 "enable-${2:-$1}" "no-${2:-$1}" " ${*:3}" ; }
	echoit() { echo "$@" ; "$@" ; }

	local krb5=$(has_version app-crypt/mit-krb5 && echo "MIT" || echo "Heimdal")

	# See if our toolchain supports __uint128_t.  If so, it's 64bit
	# friendly and can use the nicely optimized code paths. #460790
	local ec_nistp_64_gcc_128
	# Disable it for now though #469976, except for amd64
	if (use amd64 || use amd64-fbsd || use x86 || use x86-linux || use x86-fbsd) ; then
		echo "__uint128_t i;" > "${T}"/128.c
		if ${CC} ${CFLAGS} -c "${T}"/128.c -o /dev/null >&/dev/null ; then
			ec_nistp_64_gcc_128="enable-ec_nistp_64_gcc_128"
		fi
	fi

	local sslout=$(./gentoo.config)
	einfo "Use configuration ${sslout:-(openssl knows best)}"
	local config="Configure"
	[[ -z ${sslout} ]] && config="config"

	echoit \
	./${config} \
		${sslout} \
		$(use sse2 || echo "no-sse2") \
		$(use_ssl camellia) \
		$(use_ssl des) \
		enable-ec \
		${ec_nistp_64_gcc_128} -DECP_NISTZ256_ASM \
		$(use_ssl cast) \
		$(use_ssl seed) \
		$(use_ssl idea) \
		$(use_ssl mdc2) \
		$(use_ssl md4) \
		$(use_ssl rc2) \
		$(use_ssl rc4) \
		$(use_ssl rc5) \
		enable-tlsext \
		$(use_ssl gmp gmp -lgmp) \
		$(multilib_native_use_ssl kerberos krb5 --with-krb5-flavor=${krb5}) \
		$(use_ssl rfc3779) \
		$(use_ssl tls-heartbeat heartbeats -DOPENSSL_NO_HEARTBEATS) \
		$(use_ssl zlib) \
		--prefix="${EPREFIX}"/usr \
		--openssldir="${EPREFIX}"${SSL_CNF_DIR} \
		--libdir=$(get_libdir) \
		$(use cryptodev && echo "-DHAVE_CRYPTODEV -DUSE_CRYPTODEV_DIGESTS -DHASH_MAX_LEN=64") \
		shared threads \
		$(use_ssl dsa) \
		$(use_ssl ssl2) $(use_ssl ssl3) \
		$(use_ssl dtls) $(use_ssl dtls dtls1) $(use_ssl dtls dtls1_2) $(use_ssl srtp) \
		$(use_ssl blowfish bf) \
		$(use_ssl jpake) \
		$(use_ssl psk) \
		$(use_ssl srp) \
		$(use_ssl gost) \
		${EXTRA_ECONF} \
		|| die

	# Clean out hardcoded flags that openssl uses
	local CFLAG=$(grep ^CFLAG= Makefile | LC_ALL=C sed \
		-e 's:^CFLAG=::' \
		-e 's:-fomit-frame-pointer ::g' \
		-e 's:-O[0-9] ::g' \
		-e 's:-march=[-a-z0-9]* ::g' \
		-e 's:-mcpu=[-a-z0-9]* ::g' \
		-e 's:-m[a-z0-9]* ::g' \
	)
	sed -i \
		-e "/^CFLAG/s|=.*|=${CFLAG} ${CFLAGS}|" \
		-e "/^SHARED_LDFLAGS=/s|$| ${LDFLAGS}|" \
		Makefile || die
}

multilib_src_compile() {
	# depend is needed to use $confopts; it also doesn't matter
	# that it's -j1 as the code itself serializes subdirs
	emake -j1 depend
	emake all
	# rehash is needed to prep the certs/ dir; do this
	# separately to avoid parallel build issues.
	emake rehash
}

multilib_src_test() {
	emake -j1 test
}

multilib_src_install() {
	emake INSTALL_PREFIX="${D}" install
}

multilib_src_install_all() {
	dobin "${WORKDIR}"/c_rehash #333117
	dodoc CHANGES* FAQ NEWS README doc/*.txt doc/c-indentation.el
	dohtml -r doc/*
	use rfc3779 && dodoc engines/ccgost/README.gost

	# This is crappy in that the static archives are still built even
	# when USE=static-libs.  But this is due to a failing in the openssl
	# build system: the static archives are built as PIC all the time.
	# Only way around this would be to manually configure+compile openssl
	# twice; once with shared lib support enabled and once without.
	use static-libs || rm -f "${ED}"/usr/lib*/lib*.a

	# create the certs directory
	dodir ${SSL_CNF_DIR}/certs
	cp -RP certs/* "${ED}"${SSL_CNF_DIR}/certs/ || die
	rm -r "${ED}"${SSL_CNF_DIR}/certs/{demo,expired}

	# Namespace openssl programs to prevent conflicts with other man pages
	cd "${ED}"/usr/share/man
	local m d s
	for m in $(find . -type f | xargs grep -L '#include') ; do
		d=${m%/*} ; d=${d#./} ; m=${m##*/}
		[[ ${m} == openssl.1* ]] && continue
		[[ -n $(find -L ${d} -type l) ]] && die "erp, broken links already!"
		mv ${d}/{,ssl-}${m}
		# fix up references to renamed man pages
		sed -i '/^[.]SH "SEE ALSO"/,/^[.]/s:\([^(, ]*(1)\):ssl-\1:g' ${d}/ssl-${m}
		ln -s ssl-${m} ${d}/openssl-${m}
		# locate any symlinks that point to this man page ... we assume
		# that any broken links are due to the above renaming
		for s in $(find -L ${d} -type l) ; do
			s=${s##*/}
			rm -f ${d}/${s}
			ln -s ssl-${m} ${d}/ssl-${s}
			ln -s ssl-${s} ${d}/openssl-${s}
		done
	done
	[[ -n $(find -L ${d} -type l) ]] && die "broken manpage links found :("

	dodir /etc/sandbox.d #254521
	echo 'SANDBOX_PREDICT="/dev/crypto"' > "${ED}"/etc/sandbox.d/10openssl

	diropts -m0700
	keepdir ${SSL_CNF_DIR}/private
}

pkg_preinst() {
	has_version ${CATEGORY}/${PN}:0.9.8 && return 0
	preserve_old_lib /usr/$(get_libdir)/lib{crypto,ssl}.so.0.9.8
}

pkg_postinst() {
	ebegin "Running 'c_rehash ${EROOT%/}${SSL_CNF_DIR}/certs/' to rebuild hashes #333069"
	c_rehash "${EROOT%/}${SSL_CNF_DIR}/certs" >/dev/null
	eend $?

	has_version ${CATEGORY}/${PN}:0.9.8 && return 0
	preserve_old_lib_notify /usr/$(get_libdir)/lib{crypto,ssl}.so.0.9.8

	if use cryptodev; then
		einfo "Please remember:"
		einfo ""
		einfo "  modprobe cryptodev"
		einfo ""
		einfo "Use as follows:"
		einfo ""
		einfo "  shell:  openssl -evp -engine cryptodev ..."
		einfo "  apache: SSLCryptoDevice cryptodev"
		einfo "  nginx:  main {ssl_engine cryptodev; ...}"
	fi

	if use cast || use idea || use rc2 || use seed || use md4 || use mdc2; then
		elog "You are building OpenSSL with some archaic ciphers or hash functions."
	fi

	if ! use rc4; then
		ewarn
		ewarn "You need RC4 for torrents over encrypted connections."
	fi
	if ! use md4; then
		ewarn
		ewarn "SASL still needs MD4 support."
	fi
	if ! use des; then
		ewarn
		ewarn "Your OpenSSL installation has no support for DES and 3DES."
		ewarn "The latter is a mandatory cipher according to specs in TLS 1.0 and S/MIME."
	fi
	if ! use rc2; then
		ewarn
		ewarn "RC2 is a mandatory cipher in S/MIME, which is still used e.g. with MS Outlook"
		ewarn "unless you enable support for 'alternate ciphers' (= AES, SHA2) there."
	fi

	if ! (use dsa && use des && use blowfish && use cast); then
		ewarn
		ewarn "Old versions of OpenSSH will not compile and will not work."
	fi
}
