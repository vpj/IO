import * as URL from "url"
import * as PATH from "path"
import * as FS from "fs"
import * as HTTP from "http"

let CONTENT_TYPES = {
    '.js': 'text/javascript',
    '.css': 'text/css',
    '.png': 'image/png',
    '.jpg': 'image/jpg',
    '.html': 'text/html'
}

function getContentType(ext: string) {
    let type = CONTENT_TYPES[ext]
    if (type == null)
        return 'text/plain'
    else
        return type
}

interface Content {
    contentType: string
    contentString: string
}

interface Handler {
    (req: HTTP.IncomingMessage): Promise<Content>
}

export class StaticServer {
    private staticPath: string
    private ignore: Set<string>
    private handlers: { [pathname: string]: Handler }

    constructor(staticPath: string, ignore: Set<string>) {
        this.staticPath = staticPath
        this.ignore = ignore
        this.handlers = {}
    }

    addHandler(pathname: string, callback: Handler) {
        this.handlers[pathname] = callback
    }

    private invokeHandler(path: string, req: HTTP.IncomingMessage, res: HTTP.ServerResponse): boolean {
        if (!(path in this.handlers)) {
            return false;
        }

        let handler = this.handlers[path]
        let promise = handler(req)

        promise.then((content) => {
            res.writeHead(200, {
                'Content-Type': content.contentType,
                'Content-Length': Buffer.byteLength(content.contentString, 'utf8')
            });
            res.write(content.contentString)
            res.end()
        })

        return true
    }

    private serveStatic(path: string, res: HTTP.ServerResponse) {
        if ((path.indexOf('/')) === 0) {
            path = path.substr('/'.length);
        }

        if (path.length > 0 && path[0] === '.') {
            res.writeHead(403)
            res.end()
            return
        }

        if (path === '' || PATH.extname(path) == '') {
            path = 'index.html';
        }

        let ext = PATH.extname(path);
        path = PATH.join(this.staticPath, path);
        FS.readFile(path, function (err, content) {
            if (err != null) {
                res.writeHead(404)
                res.end()
            } else {
                res.writeHead(200, {
                    'Content-Type': getContentType(ext),
                    'Content-Length': content.length
                });
                return res.end(content, 'utf-8');
            }
        })
    }

    handleRequest = (req: HTTP.IncomingMessage, res: HTTP.ServerResponse) => {
        let url = URL.parse(req.url)
        let path = url.pathname;

        if (this.ignore.has(path)) {
            return false
        }

        if (this.invokeHandler(path, req, res)) {
            return true
        }

        this.serveStatic(path, res)

        return true
    }
}
