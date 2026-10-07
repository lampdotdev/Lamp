"""Composite Cycles frames onto the page and encode a forward/backward camera tour."""
import argparse
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('frames', type=Path)
parser.add_argument('destination', type=Path)
args = parser.parse_args()
missing = [frame for frame in range(97) if not (args.frames / f'{frame:04d}.png').is_file()]
if missing:
    parser.error(f'Missing rendered frames: {missing}')
args.destination.mkdir(parents=True, exist_ok=True)

# Composite in RGB before encoding; 10-bit HEVC preserves the broad, pale gradients.
filters = (
    '[0:v]format=rgba,split[foreground][background];'
    '[background]drawbox=c=0xfefdfc:t=fill:replace=1[page];'
    '[page][foreground]overlay=format=rgb:shortest=1,format=gbrp,'
    'zscale=matrixin=gbr:transferin=iec61966-2-1:primariesin=709:rangein=full:'
    'matrix=709:transfer=709:primaries=709:range=limited,format=yuv420p10le,split[forward][backward];'
    '[backward]reverse,trim=start_frame=1,setpts=PTS-STARTPTS[reverse];'
    '[forward][reverse]concat=n=2:v=1:a=0[out]'
)
movie = args.destination / 'onboarding.mp4'
subprocess.run([
    'ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-framerate', '30',
    '-i', str(args.frames / '%04d.png'), '-filter_complex', filters, '-map', '[out]',
    '-c:v', 'libx265', '-preset', 'medium', '-crf', '17', '-tag:v', 'hvc1',
    '-x265-params', 'log-level=error:keyint=48:min-keyint=48:scenecut=0',
    '-color_primaries', 'bt709', '-color_trc', 'bt709', '-colorspace', 'bt709',
    '-movflags', '+faststart', str(movie),
], check=True)

# Decode the actual resting frames, so stills and film share the same compression
# and color treatment. These also make startup and Reduce Motion instantaneous.
for step, frame in enumerate((0, 48, 96)):
    subprocess.run([
        'ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-i', str(movie),
        '-vf', f'select=eq(n\\,{frame}),zscale=matrixin=709:transferin=709:primariesin=709:rangein=limited:'
               'matrix=gbr:transfer=iec61966-2-1:primaries=709:range=full,format=gbrp,format=rgb24',
        '-frames:v', '1', str(args.destination / f'step{step}.png'),
    ], check=True)
print(f'Wrote {movie} ({movie.stat().st_size / 1024 / 1024:.1f} MB) and three resting frames')
