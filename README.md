# extract-files
Project named with the intention of adding extraction for other file types.

## extract-jpeg
extract jpeg file from disc image, block device or any other file.

requirements: ruby 1.9+
Tested on Mac and Linux, examples are from Linux.

usage: `ruby extract-jpeg.rb file [output]`

This was originaly developed to recover deleted pictures from an SD card. In such a case, it is best to make an image of the device as soon as possible. Any further use of the volume after deletion will increase chances of data being overwritten, in which case, it's just gone.

On Linux, BSD or Mac, *dd* works well for taking an image of a drive. There is plenty material on the internet to learn all about *dd*, (read the manual before using *dd*!) but I'll give a quick example here.

`dd if=/dev/sdb of=/home/mjb2k/sdcard.img bs=1M`

Notice my input (if) is sdb, not sdb1. I want to make an image of the entire device, not a partition. (This may not always be the case, especially with partioned hard drives) The output (of) is the file I want to write the image to.
Remember we are making an image of the entire device; the output file will be the disc's total capacity, not the used space. I give a block size (bs) of 1 MB becase the default size of 512 bytes is usually a bit slow.

You can now scan the disc image: `ruby extract-jpeg.rb /home/mjb2k/sdcard.img`

Or if you want to specify the output directory instead of the default 'jpeg-files', you do so like this:

`ruby extract-jpeg.rb /home/mjb2k/sdcard.img /home/mjb2k/recovered-pics`

If you do not have enough free space to make an image of the device, say if you are scanning a large hard drive, you can scan the device directly.

`sudo ruby extract-jpeg.rb /dev/sdb`

sudo is required for direct device access. **Known Issue**, percent complete and estimated time remaining is not reported correctly when scanning a device.

This should also work for extracting jpeg images embedded in other file types such as PDF. This is untested specifically, but I did notice that when extracting jpegs I was getting images known to originate form a PDF file.


Untested on Windows.
