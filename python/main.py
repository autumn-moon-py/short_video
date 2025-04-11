from pathlib import Path
import os
from fastapi.responses import FileResponse
import uvicorn
from fastapi import FastAPI


app = FastAPI(name="file_server")
VIDEO_EXTENSIONS = [".webm",".mp4"]
video_dir = "E:/video/完成"
host = "192.168.1.5"


@app.get("/")
async def ping():
    return {"msg": "服务器正常"}


@app.get("/video")
def video():
    video_files = find_videos(video_dir)
    video_urls = []
    for file_path in video_files:
        web_path = file_path.replace(video_dir, "")
        base_name = os.path.basename(web_path)
        name_without_extension = os.path.splitext(base_name)[0]
        url = f"https://{host}:8001{web_path}"
        video_urls.append([name_without_extension, url])
    return video_urls


def find_videos(directory, videos=None):
    if videos is None:
        videos = []
    for item in os.listdir(directory):
        full_path = os.path.join(directory, item)
        if os.path.isdir(full_path):
            find_videos(full_path, videos)
        elif any(item.lower().endswith(ext) for ext in VIDEO_EXTENSIONS):
            videos.append(full_path)
    return videos


def start_file_server():
    os.system(f"start video")


if __name__ == "__main__":
    start_file_server()
    uvicorn.run(app=app, host=host, port=9090)
