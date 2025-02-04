# OpenComputers-things

This repository is a collection of my OpenComputers projects.

`music.lua` is a music player that parses a custom music description language I made and plays it using the Computronics sound card. I have polished it up for public use.

`music/` is a directory containing some music files I have written. `Bad Apple!!.mus` is the main one I put a lot of work into, but there's also the much simpler `Katyusha.mus` too.

`video.lua` is a video player that takes a directory of PNG files and plays them as a video. I have not polished it up for public use, so it is full of hardcoded values and idiosyncrasies.

`play.lua` simply activates both `music.lua` and `video.lua` at the same time with the appropriate timing to play the *Bad Apple!!* music video. Note that it expects `Bad Apple!!.mus` to be in the `/home/` directory.

Here's how to play *Bad Apple!!* with this software:

- Download the video from youtube as an MP4 and name it `bad_apple.mp4` (or whatever, as long as you modify the commands below accordingly).
- Download `palette.png` from this repository.
- Install ffmpeg, if you don't already have it.
- Convert the video to frames using the following commands (assuming Linux):
```bash
mkdir frames
ffmpeg -i bad_apple.mp4 -i palette.png -filter_complex 'scale=-1:200:sws_flags=neighbor,setsar=1[a],[a][1]paletteuse' -r 10 frames/out_%04d.png
```
- Open a Minecraft world with OpenComputers (version >=1.8.0) and Computronics.
- Create a RAID and fill it with three Tier 3 HDDs.
- Put a computer next to the RAID and give it good components. Make sure the computer has a Tier 3 GPU, a data card (any tier), and a sound card. Also make sure it's connected to a Tier 3 screen, ideally of aspect ratio 3:2 or wider.
- Exit to the main menu or quit minecraft entirely (not needed if `bufferChanges` is set to false into the OpenComputers config file).
- Locate the computer's internal drive and the RAID in your game data (should be under `opencomputers/` in the save directory for your Minecraft world).
- Put the 2,000 or so frames produced by ffmpeg into a folder named `frames/` in the RAID and put `music.lua`, `Bad Apple!!.mus`, `video.lua`, and `play.lua` in the `/home/` directory in your computer's internal drive.
- Open your minecraft world again and verify that all the added data is there.
- Find the location of the RAID in the filesystem (e.g. `/mnt/3fa`) and modify lines 34 and 76 in `video.lua` to use that location.
- Finally, run `play` in the home directory and enjoy!

