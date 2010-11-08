#!/usr/bin/env sh
package_file=`ls | grep hk.ndb.quickscrollplus`
echo "== Copying package file..."
scp $package_file root@nathans-iphone:/var/mobile
echo "== Installing..."
ssh root@nathans-iphone "dpkg -r hk.ndb.quickscrollplus; cd /var/mobile; dpkg -i $package_file; killall SpringBoard"
echo "===== Done."
