#/bin/bash
# This script was made to help prevent damage to people's hardware
# when installing Linux onto media like:
#           SD, SDHC, and CPIO (compatibility issues).
#
# This script is configured for the mk802/ak802 Debian install raw disk images,
#  and will copy the system into safer tar.gz files for proper installs.
#
#  READ AND EDIT THE TARGET DRIVE SETTINGs before you run it as root.. 
#  Make sure not to delete one of your local drives...
#
# Known bugs:
# * "sfdisk" avoids damaging card geometry information like fdisk, that causes 
#    i/o performance loss and premature drive wear-out. People who used the 
#    Windows installer or "dd" can see drive slow down below the rated speeds
#
# *  Some cards force 32K FAT32 cluster sizes to fake high i/o speeds
#     even if the sector size still reads as 512 bytes. 
#
# * Some Class 10 cards will not work on older kernels
#
#
#Todo:
# * Tried to emulate cluster cylinder alignment, but the block size on
#    ext4 is 4096. Although one can make it 32768 bytes, the 
#    mount options would need the size explicitly defined.
#    I continue to look for ways to spoof a FAT32 cluster, as
#    this should make the file system work with more cards if alignment is good
#
#
#  Apache License, Version 2.0 
#  http://www.apache.org/licenses/LICENSE-2.0
#
# (c) Joel Mckay 2012  
# e-mail: j031mckay@gmail.com

#the mk802 drive image
srcdriveimage="linaro-alip-armhf.img"
#the sdhc card name in /dev/sdb
targetdrive="sdz"

 
#setup local tmp dirs
mkdir mnt
mkdir mnt2
mkdir sdbmnt
mkdir sdb2mnt
chmod 777 mnt
chmod 777 mnt2
chmod 777 sdbmnt
chmod 777 sdb2mnt

mydir=$(pwd) 

#kick any auto-mounted daemons
umount /dev/"$targetdrive"1
umount /dev/"$targetdrive"2 
umount mnt
umount mnt2


#Re-Partition drive if it has not been done already
srctarpkg=$mydir"/part_backup.bin"
if [ ! -f $srctarpkg ]
then

	echo ------------------ Backup card layout info-------------------------
	sfdisk -l -uS /dev/"$targetdrive" > "$mydir"/part_backup_info.txt
	sfdisk -d /dev/"$targetdrive" > "$mydir"/part_backup.bin

	echo ------------------ Edit card layout -------------------------
	read -p "Press [Enter] key to start card overwrite..."
	clustercount=$(fdisk -lu /dev/sdb | grep -e "total" | awk '{print $8}')
	echo clustercount=$clustercount
	sdcardid=0

	#16G Lexar card
	if [ $clustercount -eq 31275008 ]
	then
	sfdisk  --force /dev/"$targetdrive" < "$mydir"/part_16G.bin
	sdcardid=16
	fi
	 
	#32G RH Data
	if [ $clustercount -eq 65536000 ]
	then
	sfdisk  --force /dev/"$targetdrive" < "$mydir"/part_32G.bin
	sdcardid=32
	fi

	echo Remove and RE-IINSERT the newly partitioned usb card-reader
	echo and then Re-run this script
	exit 0
else
	echo Partition was already done...
fi

#Re-format drive if it has not been done already
srctarpkg=$mydir"/format_stats.txt"
if [ ! -f $srctarpkg ]
then
	echo ------------------ Format card -------------------------
	#reformat partition 1 to use 32k clusters (assume: 512b sectors) 
	dd if=/dev/zero of=/dev/"$targetdrive"1  bs=512 count=100
	mkdosfs -v -s64 -S512 -F16 -n "BOOT" /dev/"$targetdrive"1
	sync
 
	#Problematic bug that requires install modification: 
	#mkfs.ext4 -b 32768 -I 512 -j -O extent,large_file,uninit_bg,dir_index -L "ROOT" /dev/"$targetdrive"2
	dd if=/dev/zero of=/dev/"$targetdrive"2  bs=512 count=100
	mkfs.ext4 -b 4096 -I 512 -j -E stride=8,stripe-width=8  -O extent,large_file,uninit_bg,dir_index -L "ROOT" /dev/"$targetdrive"2
	sync
	 
	
	#Fast Optional performance hacks and remove slower journal safety feature
	#tune2fs -o journal_data_writeback   /dev/"$targetdrive"2
	#Faster Optional performance hacks to remove  journal safety
	#tune2fs -O ^has_journal   /dev/"$targetdrive"2
	#fsck -pDf  /dev/"$targetdrive"2
	#sync
	
	#bloat the swap block size to match cluster sizes (4096 default is too small on some cards)
	mkswap -p 32768 -L "SWAP" /dev/"$targetdrive"3
	sync
	
	#echo "format" > $srctarpkg
	
else
	echo Format was already done...
fi


echo ------------------ scan sdhc card-------------------------
echo Notes: 
echo - Bad flash-geometry/format problems can show as corrupted ext4 Journals
echo - OEM card formatting software usually can repair bad drive layouts
echo  
echo Checking $targetdrive for errors...
fsck.vfat -v /dev/"$targetdrive"1
fsck -pDf /dev/"$targetdrive"2 

#pull apart image file iff this has not been done already
srctarpkg=$mydir"/"$srcdriveimage"_p2.tar.gz"  
if [ ! -f $srctarpkg ]
then
	cd "$mydir"
	
	echo ------------------ mount image file -----------------
	mount -o loop,offset=$((512*2048)) "$srcdriveimage" mnt
	mount -o loop,offset=$((512*34816)) "$srcdriveimage" mnt2 

	echo ------ backup drive image file contents ---------
	cd "$mydir"/mnt
	tar -zcpf "$mydir"/"$srcdriveimage"_p1.tar.gz --exclude=proc --exclude=sys --exclude=dev/pts --exclude=backups .

	cd "$mydir"/mnt2
	tar -zcpf "$mydir"/"$srcdriveimage"_p2.tar.gz .
	 

else
	echo "$mydir"/"$srcdriveimage"_p2.tar.gz OS copy already done....
fi


echo ---------- mount flash drive -------------------------
cd "$mydir"
mount -tvfat /dev/"$targetdrive"1 sdbmnt
mount -text4 /dev/"$targetdrive"2 sdb2mnt
sync

echo -- Install drive image file contents on new drive -- 
cd "$mydir"/sdbmnt
tar -zxpf "$mydir"/"$srcdriveimage"_p1.tar.gz 
cd "$mydir"/sdb2mnt
tar -zxpf "$mydir"/"$srcdriveimage"_p2.tar.gz 
 
echo ------------------ clean up --------------------
cd "$mydir"
sync
umount /dev/"$targetdrive"1
umount /dev/"$targetdrive"2 
umount mnt
umount mnt2
sync
rm -rf mnt
rm -rf mnt2
rm -rf sdbmnt
rm -rf sdb2mnt

echo ------------ Install U-BOOT stripe -------------
#dd if=$mydir"/"$srcdriveimage" of="$mydir"/u-boot.bin bs=512 skip=7 count=10000

dd if="$mydir"/u-boot.bin of=/dev/$targetdrive bs=512 seek=8
sync
echo ------- Re-check the drives for errors -------
fsck.msdos  -y /dev/"$targetdrive"1
fsck.ext4 -y /dev/"$targetdrive"2 
echo ------------------ Done! -------------------------
