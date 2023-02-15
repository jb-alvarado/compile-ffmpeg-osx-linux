# FFmpeg NDI patch

Just a patch that add NDI from Newtek back in [FFmpeg](http://ffmpeg.org/). Newtek distributed FFmpeg compiled with non-free component infringing FFmpeg's license, then FFmpeg team decide to remove NDI protocol from it. ([source](https://trac.ffmpeg.org/ticket/7589))
Then I create this patch. Remember don't distribute a FFmpeg package with non-free enabled.

The patch file has for purpose to modify FFmpeg code, and other files to be added to it.
Then the licensing of those files will be and should be the same as [FFmpeg](https://git.ffmpeg.org/gitweb/ffmpeg.git/blob/HEAD:/LICENSE.md).

**Copy NDI SDK headers to `local/include` and libs from `lib/x86_64-linux-gnu` to `local/lib` and `/usr/lib64/`**
