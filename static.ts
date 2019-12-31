import { NodeHttpServerPort } from "./io_node"
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
    staticPath: string
    ignore: Set<string>
    handlers: { [pathname: string]: Handler }

    constructor(staticPath: string, ignore: Set<string>) {
        this.staticPath = staticPath
        this.ignore = ignore
        this.handlers = {}
    }

    addHandler(pathname: string, callback: Handler) {
        this.handlers[pathname] = callback
    }

    private invokeHandler(path: string, req: HTTP.IncomingMessage, res: HTTP.ServerResponse): boolean {
        console.log(path, this.handlers)
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

    private serveStatic(path: string, req: HTTP.IncomingMessage, res: HTTP.ServerResponse) {
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

        // console.log(path)
        let ext = PATH.extname(path);
        path = PATH.join('/Users/varuna/ml/annotate/ui/out', path);
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

        this.serveStatic(path, req, res)

        return true
    }
}