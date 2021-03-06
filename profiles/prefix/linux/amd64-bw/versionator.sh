# Copyright 1999-2014 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# $Id$

# @ECLASS: versionator.eclass
# @MAINTAINER:
# Jonathan Callen <jcallen@gentoo.org>
# base-system@gentoo.org
# @BLURB: functions which simplify manipulation of ${PV} and similar version strings
# @DESCRIPTION:
# This eclass provides functions which simplify manipulating $PV and similar
# variables. Most functions default to working with $PV, although other
# values can be used.
# @EXAMPLE:
# Simple Example 1: $PV is 1.2.3b, we want 1_2.3b:
#     MY_PV=$(replace_version_separator 1 '_' )
#
# Simple Example 2: $PV is 1.4.5, we want 1:
#     MY_MAJORV=$(get_major_version )
#
# Rather than being a number, the index parameter can be a separator character
# such as '-', '.' or '_'. In this case, the first separator of this kind is
# selected.
#
# There's also:
#     version_is_at_least             want      have
#  which may be buggy, so use with caution.

# @FUNCTION: estack_push
# @USAGE: <stack> [items to push]
# @DESCRIPTION:
# Push any number of items onto the specified stack.  Pick a name that
# is a valid variable (i.e. stick to alphanumerics), and push as many
# items as you like onto the stack at once.
#
# The following code snippet will echo 5, then 4, then 3, then ...
# @CODE
#		estack_push mystack 1 2 3 4 5
#		while estack_pop mystack i ; do
#			echo "${i}"
#		done
# @CODE
bestack_push() {
	[[ $# -eq 0 ]] && die "bestack_push: incorrect # of arguments"
	local stack_name="_BESTACK_$1_" ; shift
	eval ${stack_name}+=\( \"\$@\" \)
}

# @FUNCTION: estack_pop
# @USAGE: <stack> [variable]
# @DESCRIPTION:
# Pop a single item off the specified stack.  If a variable is specified,
# the popped item is stored there.  If no more items are available, return
# 1, else return 0.  See estack_push for more info.
bestack_pop() {
	[[ $# -eq 0 || $# -gt 2 ]] && die "bestack_pop: incorrect # of arguments"

	# We use the fugly _estack_xxx var names to avoid collision with
	# passing back the return value.  If we used "local i" and the
	# caller ran `estack_pop ... i`, we'd end up setting the local
	# copy of "i" rather than the caller's copy.  The _estack_xxx
	# garbage is preferable to using $1/$2 everywhere as that is a
	# bit harder to read.
	local _estack_name="_BESTACK_$1_" ; shift
	local _estack_retvar=$1 ; shift
	eval local _estack_i=\${#${_estack_name}\[@\]}
	# Don't warn -- let the caller interpret this as a failure
	# or as normal behavior (akin to `shift`)
	[[ $(( --_estack_i )) -eq -1 ]] && return 1

	if [[ -n ${_estack_retvar} ]] ; then
		eval ${_estack_retvar}=\"\${${_estack_name}\[${_estack_i}\]}\"
	fi
	eval unset ${_estack_name}\[${_estack_i}\]
}
# @FUNCTION: eshopts_push
# @USAGE: [options to `set` or `shopt`]
# @DESCRIPTION:
# Often times code will want to enable a shell option to change code behavior.
# Since changing shell options can easily break other pieces of code (which
# assume the default state), eshopts_push is used to (1) push the current shell
# options onto a stack and (2) pass the specified arguments to set.
#
# If the first argument is '-s' or '-u', we assume you want to call `shopt`
# rather than `set` as there are some options only available via that.
#
# A common example is to disable shell globbing so that special meaning/care
# may be used with variables/arguments to custom functions.  That would be:
# @CODE
#		eshopts_push -o noglob
#		for x in ${foo} ; do
#			if ...some check... ; then
#				eshopts_pop
#				return 0
#			fi
#		done
#		eshopts_pop
# @CODE
beshopts_push() {
	if [[ $1 == -[su] ]] ; then
		bestack_push beshopts "$(shopt -p)"
		[[ $# -eq 0 ]] && return 0
		shopt "$@" || die "${FUNCNAME}: bad options to shopt: $*"
	else
		bestack_push beshopts $-
		[[ $# -eq 0 ]] && return 0
		set "$@" || die "${FUNCNAME}: bad options to set: $*"
	fi
}

# @FUNCTION: eshopts_pop
# @USAGE:
# @DESCRIPTION:
# Restore the shell options to the state saved with the corresponding
# eshopts_push call.  See that function for more details.
beshopts_pop() {
	local s
	bestack_pop beshopts s || die "${FUNCNAME}: unbalanced push"
	if [[ ${s} == "shopt -"* ]] ; then
		eval "${s}" || die "${FUNCNAME}: sanity: invalid shopt options: ${s}"
	else
		set +$-     || die "${FUNCNAME}: sanity: invalid shell settings: $-"
		set -${s}   || die "${FUNCNAME}: sanity: unable to restore saved shell settings: ${s}"
	fi
}

# @FUNCTION: get_all_version_components
# @USAGE: [version]
# @DESCRIPTION:
# Split up a version string into its component parts. If no parameter is
# supplied, defaults to $PV.
#     0.8.3       ->  0 . 8 . 3
#     7c          ->  7 c
#     3.0_p2      ->  3 . 0 _ p2
#     20040905    ->  20040905
#     3.0c-r1     ->  3 . 0 c - r1
get_all_version_components() {
	beshopts_push -s extglob
	local ver_str=${1:-${PV}} result
	result=()

	# sneaky cache trick cache to avoid having to parse the same thing several
	# times.
	if [[ ${VERSIONATOR_CACHE_VER_STR} == ${ver_str} ]] ; then
		echo ${VERSIONATOR_CACHE_RESULT}
		beshopts_pop
		return
	fi
	export VERSIONATOR_CACHE_VER_STR=${ver_str}

	while [[ -n $ver_str ]] ; do
		case "${ver_str::1}" in
			# number: parse whilst we have a number
			[[:digit:]])
				result+=("${ver_str%%[^[:digit:]]*}")
				ver_str=${ver_str##+([[:digit:]])}
				;;

			# separator: single character
			[-_.])
				result+=("${ver_str::1}")
				ver_str=${ver_str:1}
				;;

			# letter: grab the letters plus any following numbers
			[[:alpha:]])
				local not_match=${ver_str##+([[:alpha:]])*([[:digit:]])}
				# Can't say "${ver_str::-${#not_match}}" in Bash 3.2
				result+=("${ver_str::${#ver_str} - ${#not_match}}")
				ver_str=${not_match}
				;;

			# huh?
			*)
				result+=("${ver_str::1}")
				ver_str=${ver_str:1}
				;;
		esac
	done

	export VERSIONATOR_CACHE_RESULT=${result[*]}
	echo ${result[@]}
	beshopts_pop
}

# @FUNCTION: get_version_components
# @USAGE: [version]
# @DESCRIPTION:
# Get the important version components, excluding '.', '-' and '_'. Defaults to
# $PV if no parameter is supplied.
#     0.8.3       ->  0 8 3
#     7c          ->  7 c
#     3.0_p2      ->  3 0 p2
#     20040905    ->  20040905
#     3.0c-r1     ->  3 0 c r1
get_version_components() {
	local c=$(get_all_version_components "${1:-${PV}}")
	echo ${c//[-._]/ }
}

# @FUNCTION: get_major_version
# @USAGE: [version]
# @DESCRIPTION:
# Get the major version of a value. Defaults to $PV if no parameter is supplied.
#     0.8.3       ->  0
#     7c          ->  7
#     3.0_p2      ->  3
#     20040905    ->  20040905
#     3.0c-r1     ->  3
get_major_version() {
	local c=($(get_all_version_components "${1:-${PV}}"))
	echo ${c[0]}
}

# @FUNCTION: get_version_component_range
# @USAGE: <range> [version]
# @DESCRIPTION:
# Get a particular component or range of components from the version. If no
# version parameter is supplied, defaults to $PV.
#    1      1.2.3       -> 1
#    1-2    1.2.3       -> 1.2
#    2-     1.2.3       -> 2.3
get_version_component_range() {
	beshopts_push -s extglob
	local c v="${2:-${PV}}" range="${1}" range_start range_end
	local -i i=-1 j=0
	c=($(get_all_version_components "${v}"))
	range_start=${range%-*}; range_start=${range_start:-1}
	range_end=${range#*-}  ; range_end=${range_end:-${#c[@]}}

	while ((j < range_start)); do
		i+=1
		((i > ${#c[@]})) && beshopts_pop && return
		[[ -n "${c[i]//[-._]}" ]] && j+=1
	done

	while ((j <= range_end)); do
		echo -n ${c[i]}
		((i > ${#c[@]})) && beshopts_pop && return
		[[ -n "${c[i]//[-._]}" ]] && j+=1
		i+=1
	done
	beshopts_pop
}

# @FUNCTION: get_after_major_version
# @USAGE: [version]
# @DESCRIPTION:
# Get everything after the major version and its separator (if present) of a
# value. Defaults to $PV if no parameter is supplied.
#     0.8.3       ->  8.3
#     7c          ->  c
#     3.0_p2      ->  0_p2
#     20040905    ->  (empty string)
#     3.0c-r1     ->  0c-r1
get_after_major_version() {
	echo $(get_version_component_range 2- "${1:-${PV}}")
}

# @FUNCTION: replace_version_separator
# @USAGE: <search> <replacement> [subject]
# @DESCRIPTION:
# Replace the $1th separator with $2 in $3 (defaults to $PV if $3 is not
# supplied). If there are fewer than $1 separators, don't change anything.
#     1 '_' 1.2.3       -> 1_2.3
#     2 '_' 1.2.3       -> 1.2_3
#     1 '_' 1b-2.3      -> 1b_2.3
# Rather than being a number, $1 can be a separator character such as '-', '.'
# or '_'. In this case, the first separator of this kind is selected.
replace_version_separator() {
	beshopts_push -s extglob
	local w c v="${3:-${PV}}"
	declare -i i found=0
	w=${1:-1}
	c=($(get_all_version_components ${v}))
	if [[ ${w} != *[[:digit:]]* ]] ; then
		# it's a character, not an index
		for ((i = 0; i < ${#c[@]}; i++)); do
			if [[ ${c[i]} == ${w} ]]; then
				c[i]=${2}
				break
			fi
		done
	else
		for ((i = 0; i < ${#c[@]}; i++)); do
			if [[ -n "${c[i]//[^-._]}" ]]; then
				found+=1
				if ((found == w)); then
					c[i]=${2}
					break
				fi
			fi
		done
	fi
	c=${c[*]}
	echo ${c// }
	beshopts_pop
}

# @FUNCTION: replace_all_version_separators
# @USAGE: <replacement> [subject]
# @DESCRIPTION:
# Replace all version separators in $2 (defaults to $PV) with $1.
#     '_' 1b.2.3        -> 1b_2_3
replace_all_version_separators() {
	local c=($(get_all_version_components "${2:-${PV}}"))
	c=${c[@]//[-._]/$1}
	echo ${c// }
}

# @FUNCTION: delete_version_separator
# @USAGE: <search> [subject]
# @DESCRIPTION:
# Delete the $1th separator in $2 (defaults to $PV if $2 is not supplied). If
# there are fewer than $1 separators, don't change anything.
#     1 1.2.3       -> 12.3
#     2 1.2.3       -> 1.23
#     1 1b-2.3      -> 1b2.3
# Rather than being a number, $1 can be a separator character such as '-', '.'
# or '_'. In this case, the first separator of this kind is deleted.
delete_version_separator() {
	replace_version_separator "${1}" "" "${2}"
}

# @FUNCTION: delete_all_version_separators
# @USAGE: [subject]
# @DESCRIPTION:
# Delete all version separators in $1 (defaults to $PV).
#     1b.2.3        -> 1b23
delete_all_version_separators() {
	replace_all_version_separators "" "${1}"
}

# @FUNCTION: get_version_component_count
# @USAGE: [version]
# @DESCRIPTION:
# How many version components are there in $1 (defaults to $PV)?
#     1.0.1       ->  3
#     3.0c-r1     ->  4
get_version_component_count() {
	local a=($(get_version_components "${1:-${PV}}"))
	echo ${#a[@]}
}

# @FUNCTION: get_last_version_component_index
# @USAGE: [version]
# @DESCRIPTION:
# What is the index of the last version component in $1 (defaults to $PV)?
# Equivalent to get_version_component_count - 1.
#     1.0.1       ->  2
#     3.0c-r1     ->  3
get_last_version_component_index() {
	echo $(($(get_version_component_count "${1:-${PV}}" ) - 1))
}

# @FUNCTION: version_is_at_least
# @USAGE: <want> [have]
# @DESCRIPTION:
# Is $2 (defaults to $PVR) at least version $1? Intended for use in eclasses
# only. May not be reliable, be sure to do very careful testing before actually
# using this.
version_is_at_least() {
	local want_s="$1" have_s="${2:-${PVR}}" r
	version_compare "${want_s}" "${have_s}"
	r=$?
	case $r in
		1|2)
			return 0
			;;
		3)
			return 1
			;;
		*)
			die "versionator compare bug [atleast, ${want_s}, ${have_s}, ${r}]"
			;;
	esac
}

# @FUNCTION: version_compare
# @USAGE: <A> <B>
# @DESCRIPTION:
# Takes two parameters (A, B) which are versions. If A is an earlier version
# than B, returns 1. If A is identical to B, return 2. If A is later than B,
# return 3. You probably want version_is_at_least rather than this function.
# May not be very reliable. Test carefully before using this.
version_compare() {
	beshopts_push -s extglob
	local ver_a=${1} ver_b=${2} parts_a parts_b
	local cur_tok_a cur_tok_b num_part_a num_part_b
	local -i cur_idx_a=0 cur_idx_b=0 prev_idx_a prev_idx_b
	parts_a=( $(get_all_version_components "${ver_a}" ) )
	parts_b=( $(get_all_version_components "${ver_b}" ) )

	### compare number parts.
	local -i inf_loop=0
	while true; do
		inf_loop+=1
		((inf_loop > 20)) && \
			die "versionator compare bug [numbers, ${ver_a}, ${ver_b}]"

		# Store the current index to test later
		prev_idx_a=cur_idx_a
		prev_idx_b=cur_idx_b

		# grab the current number components
		cur_tok_a=${parts_a[cur_idx_a]}
		cur_tok_b=${parts_b[cur_idx_b]}

		# number?
		if [[ -n ${cur_tok_a} ]] && [[ -z ${cur_tok_a//[[:digit:]]} ]] ; then
			cur_idx_a+=1
			[[ ${parts_a[cur_idx_a]} == . ]] \
				&& cur_idx_a+=1
		else
			cur_tok_a=
		fi

		if [[ -n ${cur_tok_b} ]] && [[ -z ${cur_tok_b//[[:digit:]]} ]] ; then
			cur_idx_b+=1
			[[ ${parts_b[cur_idx_b]} == . ]] \
				&& cur_idx_b+=1
		else
			cur_tok_b=
		fi

		# done with number components?
		[[ -z ${cur_tok_a} && -z ${cur_tok_b} ]] && break

		# if a component is blank, then it is the lesser value
		[[ -z ${cur_tok_a} ]] && beshopts_pop && return 1
		[[ -z ${cur_tok_b} ]] && beshopts_pop && return 3

		# According to PMS, if we are *not* in the first number part, and either
		# token begins with "0", then we use a different algorithm (that
		# effectively does floating point comparison)
		if (( prev_idx_a != 0 && prev_idx_b != 0 )) \
			&& [[ ${cur_tok_a} == 0* || ${cur_tok_b} == 0* ]] ; then

			# strip trailing zeros
			cur_tok_a=${cur_tok_a%%+(0)}
			cur_tok_b=${cur_tok_b%%+(0)}

			# do a *string* comparison of the resulting values: 2 > 11
			[[ ${cur_tok_a} < ${cur_tok_b} ]] && beshopts_pop && return 1
			[[ ${cur_tok_a} > ${cur_tok_b} ]] && beshopts_pop && return 3
		else
			# to avoid going into octal mode, strip any leading zeros. otherwise
			# bash will throw a hissy fit on versions like 6.3.068.
			cur_tok_a=${cur_tok_a##+(0)}
			cur_tok_b=${cur_tok_b##+(0)}

			# now if a component is blank, it was originally 0 -- make it so
			: ${cur_tok_a:=0}
			: ${cur_tok_b:=0}

			# compare
			((cur_tok_a < cur_tok_b)) && beshopts_pop && return 1
			((cur_tok_a > cur_tok_b)) && beshopts_pop && return 3
		fi
	done

	### number parts equal. compare letter parts.
	local letter_a=
	letter_a=${parts_a[cur_idx_a]}
	if [[ ${#letter_a} -eq 1 && -z ${letter_a/[a-z]} ]] ; then
		cur_idx_a+=1
	else
		letter_a=@
	fi

	local letter_b=
	letter_b=${parts_b[cur_idx_b]}
	if [[ ${#letter_b} -eq 1 && -z ${letter_b/[a-z]} ]] ; then
		cur_idx_b+=1
	else
		letter_b=@
	fi

	# compare
	[[ ${letter_a} < ${letter_b} ]] && beshopts_pop && return 1
	[[ ${letter_a} > ${letter_b} ]] && beshopts_pop && return 3

	### letter parts equal. compare suffixes in order.
	inf_loop=0
	while true ; do
		inf_loop+=1
		((inf_loop > 20)) && \
			die "versionator compare bug [numbers, ${ver_a}, ${ver_b}]"
		[[ ${parts_a[cur_idx_a]} == _ ]] && ((cur_idx_a++))
		[[ ${parts_b[cur_idx_b]} == _ ]] && ((cur_idx_b++))

		cur_tok_a=${parts_a[cur_idx_a]}
		cur_tok_b=${parts_b[cur_idx_b]}
		num_part_a=0
		num_part_b=0

		if has ${cur_tok_a%%+([0-9])} "alpha" "beta" "pre" "rc" "p"; then
			cur_idx_a+=1
			num_part_a=${cur_tok_a##+([a-z])}
			# I don't like octal
			num_part_a=${num_part_a##+(0)}
			: ${num_part_a:=0}
			cur_tok_a=${cur_tok_a%%+([0-9])}
		else
			cur_tok_a=
		fi

		if has ${cur_tok_b%%+([0-9])} alpha beta pre rc p; then
			cur_idx_b+=1
			num_part_b=${cur_tok_b##+([a-z])}
			# I still don't like octal
			num_part_b=${num_part_b##+(0)}
			: ${num_part_b:=0}
			cur_tok_b=${cur_tok_b%%+([0-9])}
		else
			cur_tok_b=
		fi

		if [[ ${cur_tok_a} != ${cur_tok_b} ]]; then
			local suffix
			for suffix in alpha beta pre rc "" p; do
				[[ ${cur_tok_a} == ${suffix} ]] && beshopts_pop && return 1
				[[ ${cur_tok_b} == ${suffix} ]] && beshopts_pop && return 3
			done
		elif [[ -z ${cur_tok_a} && -z ${cur_tok_b} ]]; then
			break
		else
			((num_part_a < num_part_b)) && beshopts_pop && return 1
			((num_part_a > num_part_b)) && beshopts_pop && return 3
		fi
	done

	# At this point, the only thing that should be left is the -r# part
	[[ ${parts_a[cur_idx_a]} == - ]] && ((cur_idx_a++))
	[[ ${parts_b[cur_idx_b]} == - ]] && ((cur_idx_b++))

	# Sanity check
	if [[ ${parts_a[cur_idx_a]/r+([0-9])} || ${parts_b[cur_idx_b]/r+([0-9])} ]]; then
		die "versionator compare bug [revisions, ${ver_a}, ${ver_b}]"
	fi

	num_part_a=${parts_a[cur_idx_a]#r}
	num_part_a=${num_part_a##+(0)}
	: ${num_part_a:=0}
	num_part_b=${parts_b[cur_idx_b]#r}
	num_part_b=${num_part_b##+(0)}
	: ${num_part_b:=0}

	((num_part_a < num_part_b)) && beshopts_pop && return 1
	((num_part_a > num_part_b)) && beshopts_pop && return 3

	### no differences.
	beshopts_pop
	return 2
}

# @FUNCTION: version_sort
# @USAGE: <version> [more versions...]
# @DESCRIPTION:
# Returns its parameters sorted, highest version last. We're using a quadratic
# algorithm for simplicity, so don't call it with more than a few dozen items.
# Uses version_compare, so be careful.
version_sort() {
	beshopts_push -s extglob
	local items=
	local -i left=0
	items=("$@")
	while ((left < ${#items[@]})); do
		local -i lowest_idx=left
		local -i idx=lowest_idx+1
		while ((idx < ${#items[@]})); do
			version_compare "${items[lowest_idx]}" "${items[idx]}"
			[[ $? -eq 3 ]] && lowest_idx=idx
			idx+=1
		done
		local tmp=${items[lowest_idx]}
		items[lowest_idx]=${items[left]}
		items[left]=${tmp}
		left+=1
	done
	echo ${items[@]}
	beshopts_pop
}

# @FUNCTION: version_format_string
# @USAGE: <format> [version]
# @DESCRIPTION:
# Reformat complicated version strings.  The first argument is the string
# to reformat with while the rest of the args are passed on to the
# get_version_components function.  You should make sure to single quote
# the first argument since it'll have variables that get delayed expansions.
# @EXAMPLE:
# P="cow-hat-1.2.3_p4"
# MY_P=$(version_format_string '${PN}_source_$1_$2-$3_$4')
# Now MY_P will be: cow-hat_source_1_2-3_p4
version_format_string() {
	local fstr=$1
	shift
	set -- $(get_version_components "$@")
	eval echo "${fstr}"
}

