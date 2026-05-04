import argparse
import os
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse


class SpaRequestHandler(SimpleHTTPRequestHandler):
    def send_head(self):
        request_path = urlparse(self.path).path
        file_path = self.translate_path(request_path)
        basename = os.path.basename(request_path)

        if not os.path.exists(file_path) and "." not in basename:
            self.path = "/index.html"

        return super().send_head()

    def log_message(self, format, *args):
        return


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("directory")
    parser.add_argument("port", type=int)
    args = parser.parse_args()

    handler = lambda *handler_args, **handler_kwargs: SpaRequestHandler(
        *handler_args,
        directory=args.directory,
        **handler_kwargs,
    )
    server = ThreadingHTTPServer(("127.0.0.1", args.port), handler)
    print(f"Server running at http://127.0.0.1:{args.port}/")
    server.serve_forever()


if __name__ == "__main__":
    main()
