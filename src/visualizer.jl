mutable struct ViewerWindow
    context::ZMQ.Context
    socket::ZMQ.Socket
    web_url::String
    zmq_url::String
    bridge::Union{ZMQWebSocketBridge, Void}

    function ViewerWindow(bridge::ZMQWebSocketBridge)
        context = ZMQ.Context()
        socket = ZMQ.Socket(context, ZMQ.REQ)
        ZMQ.connect(socket, zmq_url(bridge))
        new(context, socket, web_url(bridge), zmq_url(bridge), bridge)
    end

    function ViewerWindow(zmq_url::AbstractString)
        context = ZMQ.Context()
        socket = ZMQ.Socket(context, ZMQ.REQ)
        ZMQ.connect(socket, zmq_url)
        web_url = request_zmq_url(socket)
        # Connect again, to work around weird bug in the Python version of the
        # server. See https://github.com/rdeits/meshcat-python/pull/2
        socket = ZMQ.Socket(context, ZMQ.REQ)
        ZMQ.connect(socket, zmq_url)
        new(context, socket, web_url, zmq_url, nothing)
    end

    function ViewerWindow()
        bridge = ZMQWebSocketBridge()
        @async run(bridge)
        ViewerWindow(bridge)
    end
end

function request_zmq_url(socket::ZMQ.Socket)
    ZMQ.send(socket, "url")
    zmq_url = unsafe_string(ZMQ.recv(socket))
end

url(c::ViewerWindow) = c.web_url
Base.open(c::ViewerWindow) = open_url(url(c))
function Base.close(c::ViewerWindow)
    close(c.socket)
    close(c.context)
end

function Base.wait(c::ViewerWindow)
    ZMQ.send(c.socket, "wait")
    ZMQ.recv(c.socket)
    nothing
end

function Base.send(c::ViewerWindow, cmd::AbstractCommand)
    data = lower(cmd)
    ZMQ.send(c.socket, data["type"], true)
    ZMQ.send(c.socket, data["path"], true)
    ZMQ.send(c.socket, pack(data), false)
    ZMQ.recv(c.socket)
    nothing
end

function open_url(url)
    @show url
    try
        @static if is_windows()
            run(`start $url`)
        elseif is_apple()
            run(`open $url`)
        elseif is_linux()
            run(`xdg-open $url`)
        end
    catch e
        println("Could not open browser automatically: $e")
        println("Please open the following URL in your browser:")
        println(url)
    end
end

struct Visualizer
    window::ViewerWindow
    path::Path
end

Visualizer() = Visualizer(ViewerWindow(), ["meshcat"])
Visualizer(zmq_url::AbstractString) = Visualizer(ViewerWindow(zmq_url), ["meshcat"])

url(v::Visualizer) = url(v.window)
Base.open(v::Visualizer) = (open(v.window); v)
Base.close(v::Visualizer) = close(v.window)
Base.show(io::IO, v::Visualizer) = print(io, "MeshCat Visualizer at $(url(v)) with path $(v.path)")
Base.wait(v::Visualizer) = wait(v.window)

function setobject!(vis::Visualizer, obj::AbstractObject)
    send(vis.window, SetObject(obj, vis.path))
    vis
end

setobject!(vis::Visualizer, geom::GeometryLike) = setobject!(vis, Mesh(geom))
setobject!(vis::Visualizer, cloud::PointCloud) = setobject!(vis, Points(cloud))
setobject!(vis::Visualizer, geom::GeometryLike, material::AbstractMaterial) = setobject!(vis, Mesh(geom, material))

function settransform!(vis::Visualizer, tform::Transformation)
    send(vis.window, SetTransform(tform, vis.path))
    vis
end

function delete!(vis::Visualizer)
    send(vis.window, Delete(vis.path))
    vis
end

Base.getindex(vis::Visualizer, path::Union{Symbol, AbstractString}...) = Visualizer(vis.window, vcat(vis.path, path...))

