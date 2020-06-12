rsync_homedir() { # $1 is user, $2 is progress. confirms restoration and rsyncs the homedir of a restored account. also executes phpfpm conversion, suspension, and perm fixes, as well as a few extra syncs for final syncs.
	local user=$1
	local progress="$2 | $user:"
	if [ -f "$dir/etc/passwd" ]; then
		local userhome_remote=`grep ^$user: $dir/etc/passwd | tail -n1 |cut -d: -f6`
		local userhome_local=`eval echo ~${user}`
		# check if cpanel user exists
		if [ -f $dir/var/cpanel/users/$user ] && [ -f /var/cpanel/users/$user ] && [ $userhome_local ] && [ $userhome_remote ] && [ -d $userhome_local ] && sssh "[ -d $userhome_remote ]"; then
			# comment out crons
			if [ "$synctype" != "final" ] && [ "$comment_crons" ] && [ -f /var/spool/cron/$user ]; then
				ec brown "$progress Commenting out crons for $user..."
				sed -i 's/^\([^#]\)/#\1/g' /var/spool/cron/$user
			fi

			# test for public_html symlink on non-final syncs
			if [ "$synctype" != "final" ]; then
				if `sssh "[ -h $userhome_remote/public_html ]"` && [ ! -h $userhome_local/public_html ]; then
					mkdir -p $dir/public_html_symlink_baks/$user
					mv $userhome_local/public_html $dir/public_html_symlink_baks/$user/
					ec brown "$progress Source public_html is symlink, moved $user's public_html to $dir/public_html_symlink_baks/$user/public_html." | errorlogit 4
				fi
			fi
			# collect quotas for rsync status printing
			local remote_quotaline=$(sssh "repquota -s \$(df -P $userhome_remote | tail -1 | awk '{print \$6}') 2> /dev/null" | grep ^${user}\ )
			local remote_quota=$(echo $remote_quotaline | awk '{print $3}')
			local remote_inodes=$(echo $remote_quotaline | awk '/+-|++/ {print $7;next} /--|-+/ {print $6}')
			ec lightGreen "$progress Rsyncing homedir (${remote_quota:-no quota} used with ${remote_inodes:-no inode quota} inodes)..."

			# perform file copies
			if [[ "$synctype" == "final" || "$synctype" == "update" ]] && [ $maildelete ]; then
				# if using --delete on maildir
				rsync $rsyncargs $rsync_update $rsync_excludes --exclude=mail -e "ssh $sshargs" $ip:$userhome_remote/ $userhome_local/ &> $dir/log/rsync.${user}.log
				[ $? -ne 0 -a $? -ne 24 ] && ec red "$progress Rsync task for $user returned nonzero exit code! This may need to get resynced (cat $dir/log/rsync.${user}.log)!" | errorlogit 2
				rsync $rsyncargs $rsync_update $rsync_excludes -e "ssh $sshargs" $ip:$userhome_remote/mail $userhome_local/ --delete &> $dir/log/rsync.${user}.log #mail --delete function
				[ $? -ne 0 -a $? -ne 24 ] && ec red "$progress Rsync task for $user returned nonzero exit code! This may need to get resynced (cat $dir/log/rsync.${user}.log)!" | errorlogit 2
			else
				# normal rsync
				rsync $rsyncargs $rsync_update $rsync_excludes -e "ssh $sshargs" $ip:$userhome_remote/ $userhome_local/ &> $dir/log/rsync.${user}.log
				[ $? -ne 0 -a $? -ne 24 ] && ec red "$progress Rsync task for $user returned nonzero exit code! This may need to get resynced (cat $dir/log/rsync.${user}.log)!" | errorlogit 2
			fi

			# optionally convert to FPM
			if [ "$fcgiconvert" ]; then
				ec white "$progress Converting domains to PHP-FPM..."
				for dom in `cat /etc/userdomains | grep \ ${user}$`; do #run twice, to set non-inherit version and then turn on fpm
					/usr/local/cpanel/bin/whmapi1 php_set_vhost_versions version=$defaultea4profile php_fpm=1 vhost-0=$dom 2>&1 | stderrlogit 3
					/usr/local/cpanel/bin/whmapi1 php_set_vhost_versions version=$defaultea4profile php_fpm=1 vhost-0=$dom 2>&1 | stderrlogit 3
				done
			fi

			# resync several items on final: crons, valiases, ftp accounts, system pass
			if [ "$synctype" = "final" ]; then
				[ -f $dir/var/spool/cron/$user ] && rsync $rsyncargs -e "ssh $sshargs" $ip:/var/spool/cron/$user /var/spool/cron/
				[ -f /var/spool/cron/$user ] && chown $user:root /var/spool/cron/$user
				[ -f $dir/etc/proftpd/$user ] && rsync $rsyncargs $dir/etc/proftpd/$user /etc/proftpd/ 2>&1 | stderrlogit 3
				remotehash=$(sssh "grep ^$user\: /etc/shadow | cut -d: -f1-2")
				if [ ! "${remotehash}" = "$(grep ^$user\: /etc/shadow | cut -d: -f1-2)" ]; then
					ec brown "$progress Linux password changed, updating on target..." | errorlogit 4
					echo $remotehash | chpasswd -e 2>&1 | stderrlogit 3
				fi
				for dom in `cat /etc/userdomains | grep \ ${user}$ | cut -d: -f1`; do
					rsync $rsyncargs -e "ssh $sshargs" $ip:/etc/valiases/$dom /etc/valiases/ --update 2>&1 | stderrlogit 4
				done
			fi

			# fixperms
			if [ $fixperms ]; then
				ec brown "$progress Fixing permissions..."
				sh /home/fixperms.sh $user 2>&1 | stderrlogit 4
			fi

			# suspend suspended accounts
			if grep -q -E '^SUSPENDED[ ]?=[ ]?1' $dir/var/cpanel/users/$user; then
				ec brown "$progress User is suspended on source server, suspending on target..." | errorlogit 4
				/scripts/suspendacct $user 2>&1 | stderrlogit 4
			fi
		else
			# restore failed
			ec red "Warning: Cpanel user $user homedir paths not found! Not rsycing homedir." | errorlogit 2
		fi
	else
		# problem with remote files
		ec lightRed "Error: Password file from remote server not found at $dir/etc/passwd, can't sync homedir for $user! " | errorlogit 2
		echo $user >> $dir/did_not_restore.txt
	fi
}
