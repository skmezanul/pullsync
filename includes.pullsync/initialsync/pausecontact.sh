pausecontact() { #back up email address in whm and change it to devnull
	ec yellow "Interrupting WHM emails..."
	# back up the contact email and root forwarder
	[ ! -f $dir/whmcontact.txt ] && grep ^CONTACTEMAIL\  /etc/wwwacct.conf | awk '{print $2}' > $dir/whmcontact.txt
	/usr/local/cpanel/bin/whmapi1 get_user_email_forward_destination user=root | grep \ -\  | awk '{print $2}' > $dir/.forward
	# move forwarder out of the way and set the forward destination to nothing
	[ -f /root/.forward ] && mv /root/.forward{,.syncbak}
	/usr/local/cpanel/bin/whmapi1 set_user_email_forward_destination user=root forward_to='' 2>&1 | stderrlogit 3
	# set the contact address to devnull
	sed -i.pullsync.bak 's/\(^CONTACTEMAIL\).*/\1 devnull@sourcedns.com/;s/\(^CONTACTPAGER\).*/\1 devnull@sourcedns.com/' /etc/wwwacct.conf
}
