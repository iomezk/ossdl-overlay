# Copyright 2006-2009 Ossdl.de, Hurrikane Systems
# Distributed under the terms of the GNU General Public License v2
# $Header:  $

DESCRIPTION="Basic applications for any LAMPP configuration."
HOMEPAGE="http://www.ossdl.de/"

LICENSE="GPL-2 Apache-2.0 BSD"
SLOT="0"
KEYWORDS="amd64 arm ~sparc x86"
IUSE=""

RDEPEND="
	sys-meta/sys-base
	>=virtual/mysql-5.1
	arm? ( www-servers/nginx[libatomic] dev-lang/php[fpm] )
	|| ( >=www-servers/apache-2.2.14 >=www-servers/nginx-0.8.20 )
	>=www-apache/mod_macro-1.1.10
	>=dev-lang/php-5.2.10
	dev-php/PEAR-PEAR
	dev-php5/eaccelerator
	dev-php5/pecl-fileinfo
	dev-php5/pecl-idn
	>=dev-util/subversion-1.6.3
	>=net-misc/memcached-1.4.0
	>=net-misc/spread-1.4.0
	"