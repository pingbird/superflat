import 'dart:async';
import 'dart:html';
import 'dart:js';
import 'dart:math';
import 'dart:typed_data';
import 'dart:web_gl';

import 'package:superflat/sprite.dart';
import 'package:meta/meta.dart';
import 'package:tuple/tuple.dart';
import 'package:vector_math/vector_math.dart';
import 'package:pedantic/pedantic.dart';
import 'package:meta/meta.dart';

class GLShader {
  GLShader(GLViewport ctx, String vertSrc, String fragSrc) {
    var gl = ctx.gl;

    var fragShader = gl.createShader(WebGL.FRAGMENT_SHADER);
    gl.shaderSource(fragShader, fragSrc);
    gl.compileShader(fragShader);

    if (!gl.getShaderParameter(fragShader, WebGL.COMPILE_STATUS)) {
      window.console.error("Errror in fragment shader");
      throw gl.getShaderInfoLog(fragShader);
    }

    var vertShader = gl.createShader(WebGL.VERTEX_SHADER);
    gl.shaderSource(vertShader, vertSrc);
    gl.compileShader(vertShader);

    if (!gl.getShaderParameter(vertShader, WebGL.COMPILE_STATUS)) {
      window.console.error("Errror in vertex shader");
      throw gl.getShaderInfoLog(vertShader);
    }

    program = gl.createProgram();
    gl.attachShader(program, vertShader);
    gl.attachShader(program, fragShader);
    gl.linkProgram(program);

    if (!gl.getProgramParameter(program, WebGL.LINK_STATUS)) {
      window.console.error("Error linking shader");
      throw gl.getProgramInfoLog(program);
    }

    var nAttribs = gl.getProgramParameter(program, WebGL.ACTIVE_ATTRIBUTES);
    for (int i = 0; i < nAttribs; i++) {
      var info = gl.getActiveAttrib(program, i);
      var l = gl.getAttribLocation(program, info.name);
      gl.enableVertexAttribArray(i);
      attributes[info.name] = l;
    }

    var nUniforms = gl.getProgramParameter(program, WebGL.ACTIVE_UNIFORMS);
    for (int i = 0; i < nUniforms; i++) {
      var info = gl.getActiveUniform(program, i);
      uniforms[info.name] = gl.getUniformLocation(program, info.name);
    }
  }

  static Future<GLShader> load(GLViewport ctx, List<String> vertAssets, List<String> fragAssets) async {
    List<String> vertSource = await Stream.fromIterable(vertAssets).asyncMap(HttpRequest.getString).toList();
    List<String> fragSource = await Stream.fromIterable(fragAssets).asyncMap(HttpRequest.getString).toList();
    return GLShader(ctx, vertSource.join("\n"), fragSource.join("\n"));
  }

  Program program;
  var attributes = <String, int>{};
  var uniforms = <String, UniformLocation>{};
}

class GLObject {
  GLViewport ctx;

  Future init() async {}
  void tick(num dt) {}
  void draw() {}
  void dispose() {}

  bool initialized = false;
}

class GLViewport {
  GLApp app;

  int width;
  int height;

  Matrix4 pMatrix;
  Matrix4 mvMatrix;
  List<Matrix4> mvStack = [];

  mvPush() => mvStack.add(mvMatrix.clone());
  mvPop() => mvMatrix = mvStack.removeLast();

  RenderingContext gl;
  JsObject glJs;

  GLViewport(this.app) {
    gl = app.gl;
    glJs = app.glJs;
  }

  void dispose() {}

  void draw() {
    gl.viewport(0, 0, width, height);
    gl.clearColor(0.05, 0.05, 0.05, 1);
    gl.clear(WebGL.COLOR_BUFFER_BIT | WebGL.DEPTH_BUFFER_BIT);
    gl.enable(WebGL.DEPTH_TEST);
    gl.disable(WebGL.BLEND);

    var fh = tan(radians(45.0) * 0.5) * 0.1;
    var fw = fh * (width / height);
    pMatrix = makeFrustumMatrix(-fw, fw, -fh, fh, 0.1, 100.0);

    mvStack = [];
  }

  Map<String, JsObject> objCache = {};

  FutureOr<JsObject> loadObj(String url) async {
    if (objCache.containsKey(url)) return objCache[url];
    var obj = JsObject(context["OBJ"]["Mesh"], [await HttpRequest.getString(url)]);
    (context["OBJ"]["initMeshBuffers"] as JsFunction).apply([glJs, obj]);
    objCache[url] = obj;
    return obj;
  }

  Map<Tuple2<String, String>, GLShader> shaderCache = {};

  FutureOr<GLShader> loadShader(String vert, String frag) async {
    var key = Tuple2(vert, frag);
    if (shaderCache.containsKey(key)) return shaderCache[key];

    var shader = GLShader(this,
      await HttpRequest.getString(vert),
      await HttpRequest.getString(frag),
    );

    shaderCache[key] = shader;
    return shader;
  }

  Map<Tuple5<String, int, int, int, int>, Texture> imageCache = {};

  FutureOr<Texture> loadTexture(String url, {
    int level = 0,
    int internalFormat = WebGL.RGBA,
    int srcFormat = WebGL.RGBA,
    int srcType = WebGL.UNSIGNED_BYTE,
  }) async {
    var key = Tuple5(url, level, internalFormat, srcFormat, srcType);
    if (imageCache.containsKey(key)) return imageCache[key];

    var texture = gl.createTexture();

    var img = ImageElement()..src = url;
    await img.onLoad.first;

    gl.bindTexture(WebGL.TEXTURE_2D, texture);
    gl.texImage2D(WebGL.TEXTURE_2D, level, internalFormat, srcFormat, srcType, img);

    bool po2(int x) => x & (x - 1) == 0;

    if (po2(img.width) && po2(img.height)) {
      gl.generateMipmap(WebGL.TEXTURE_2D);
    } else {
      gl.texParameteri(WebGL.TEXTURE_2D, WebGL.TEXTURE_WRAP_S, WebGL.CLAMP_TO_EDGE);
      gl.texParameteri(WebGL.TEXTURE_2D, WebGL.TEXTURE_WRAP_T, WebGL.CLAMP_TO_EDGE);
      gl.texParameteri(WebGL.TEXTURE_2D, WebGL.TEXTURE_MIN_FILTER, WebGL.LINEAR);
    }

    imageCache[key] = texture;
    return texture;
  }
}

class GLFilter extends GLObject {
  GLViewport ctx;
  GLShader shader;

  GLFilter(this.ctx, this.shader);

  Texture texture;

  void draw() {
    var gl = ctx.gl;
    gl.activeTexture(WebGL.TEXTURE0);
    gl.bindTexture(WebGL.TEXTURE_2D, texture);
    gl.useProgram(shader.program);
    gl.bindBuffer(WebGL.ARRAY_BUFFER, ctx.app.squareBuf);
    gl.vertexAttribPointer(shader.attributes["aPos"], 2, WebGL.FLOAT, false, 0, 0);
    gl.uniform1i(shader.uniforms["uTex"], 0);
    gl.drawArrays(WebGL.TRIANGLES, 0, 6);
  }
}

class GLApp {
  GLApp(this.canvas) {
    resizeObserver = ResizeObserver((l, r) {
      updateSize();
    })..observe(canvas);

    gl = canvas.getContext3d();
    glJs = JsObject.fromBrowserObject(gl.canvas).callMethod("getContext", ["webgl"]);
    viewport = GLViewport(this);
    updateSize();

    lastDraw = DateTime.now().millisecondsSinceEpoch;
  }

  CanvasElement canvas;
  GLViewport viewport;
  RenderingContext gl;
  JsObject glJs;
  Framebuffer framebuffer;
  Texture framebufferTex;
  Texture framebufferTex2;
  Texture depthTex;

  ResizeObserver resizeObserver;
  double time = 0.0;
  double oversample = 2.0;

  Buffer squareBuf;

  Map<String, JsObject> webglExt = {};

  Object getWebGLExt(String name) {
    if (webglExt.containsKey(name)) return webglExt[name];
    var ext = glJs.callMethod("getExtension", [name]);
    if (ext == null) throw "Could not load extension '$name'";
    print("Loaded WebGL extension '$name'");
    webglExt[name] = ext as JsObject;
    return ext;
  }

  Future init() async {
    getWebGLExt("OES_texture_half_float");
    getWebGLExt("OES_texture_half_float_linear");
    getWebGLExt("WEBGL_depth_texture");

    framebufferTex = gl.createTexture();
    framebufferTex2 = gl.createTexture();
    framebuffer = gl.createFramebuffer();

    depthTex = gl.createTexture();

    gl.bindTexture(WebGL.TEXTURE_2D, depthTex);
    gl.texImage2D(WebGL.TEXTURE_2D, 0, WebGL.DEPTH_COMPONENT, viewport.width, viewport.height, 0, WebGL.DEPTH_COMPONENT, WebGL.UNSIGNED_SHORT);
    gl.texParameteri(WebGL.TEXTURE_2D, WebGL.TEXTURE_MAG_FILTER, WebGL.NEAREST);
    gl.texParameteri(WebGL.TEXTURE_2D, WebGL.TEXTURE_MIN_FILTER, WebGL.NEAREST);
    gl.texParameteri(WebGL.TEXTURE_2D, WebGL.TEXTURE_WRAP_S, WebGL.CLAMP_TO_EDGE);
    gl.texParameteri(WebGL.TEXTURE_2D, WebGL.TEXTURE_WRAP_T, WebGL.CLAMP_TO_EDGE);

    for (var obj in objects) {
      obj.ctx = viewport;
      await obj.init();
      obj.initialized = true;
    }

    squareBuf = gl.createBuffer();
    gl.bindBuffer(WebGL.ARRAY_BUFFER, squareBuf);
    gl.bufferData(WebGL.ARRAY_BUFFER, Float32List.fromList([
      0, 0, 0, 1, 1, 0, 1, 0, 0, 1, 1, 1,
    ]), WebGL.STATIC_DRAW);

    updateSize();
  }

  Future addObject(GLObject obj) async {
    obj.ctx = viewport;
    await obj.init();
    obj.initialized;
    if (obj is GLFilter) {
      filters.add(obj);
    } else {
      objects.add(obj);
    }
  }

  void updateFramebufferSize(Texture tex) {
    if (tex == null) return;
    gl.bindTexture(WebGL.TEXTURE_2D, tex);

    gl.texImage2D(
      WebGL.TEXTURE_2D, 0, WebGL.RGBA,
      viewport.width, viewport.height, 0,
      WebGL.RGBA, webglExt["OES_texture_half_float"]["HALF_FLOAT_OES"], null
    );

    gl.texParameteri(WebGL.TEXTURE_2D, WebGL.TEXTURE_WRAP_S, WebGL.CLAMP_TO_EDGE);
    gl.texParameteri(WebGL.TEXTURE_2D, WebGL.TEXTURE_WRAP_T, WebGL.CLAMP_TO_EDGE);
    gl.texParameteri(WebGL.TEXTURE_2D, WebGL.TEXTURE_MIN_FILTER, WebGL.LINEAR);
    gl.bindTexture(WebGL.TEXTURE_2D, null);
  }

  void updateSize() {
    canvas.width = canvas.clientWidth * 2;
    canvas.height = canvas.clientHeight * 2;
    viewport.width = (canvas.width * oversample).round();
    viewport.height = (canvas.height * oversample).round();
    updateFramebufferSize(framebufferTex);
    updateFramebufferSize(framebufferTex2);
  }

  List<GLObject> objects = [];
  List<GLFilter> filters = [];

  int lastDraw;
  bool drawing = false;

  void draw() {
    if (canvas == null) return;

    if (canvas.width != 0 && canvas.height != 0) {
      viewport.mvMatrix = Matrix4.identity();
      var now = DateTime.now().millisecondsSinceEpoch;
      for (var obj in objects) obj.tick((now - lastDraw) / 1000);
      lastDraw = now;

      gl.bindFramebuffer(WebGL.FRAMEBUFFER, framebuffer);
      gl.framebufferTexture2D(WebGL.FRAMEBUFFER, WebGL.COLOR_ATTACHMENT0, WebGL.TEXTURE_2D, framebufferTex, 0);
      gl.framebufferTexture2D(WebGL.FRAMEBUFFER, WebGL.DEPTH_ATTACHMENT, WebGL.TEXTURE_2D, depthTex, 0);

      gl.enable(WebGL.DEPTH_TEST);
      viewport.draw();
      for (var obj in objects) obj.draw();

      var a = framebufferTex;
      var b = framebufferTex2;
      for (var filt in filters) {
        if (filt == filters.last) {
          gl.bindFramebuffer(WebGL.FRAMEBUFFER, null);
          gl.viewport(0, 0, canvas.width, canvas.height);
          gl.clearColor(1, 0.4, 1, 1);
          gl.clear(WebGL.COLOR_BUFFER_BIT | WebGL.DEPTH_BUFFER_BIT);
        } else {
          gl.framebufferTexture2D(WebGL.FRAMEBUFFER, WebGL.COLOR_ATTACHMENT0, WebGL.TEXTURE_2D, a, 0);
          gl.framebufferTexture2D(WebGL.FRAMEBUFFER, WebGL.DEPTH_ATTACHMENT, WebGL.TEXTURE_2D,depthTex, 0);
        }

        filt.texture = a;
        filt.draw();

        var t = b;
        b = a;
        a = t;
      }
    }

    if (drawing) window.animationFrame.then((_) {
      draw();
    });
  }

  void start() {
    drawing = true;
    window.animationFrame.then((_) {
      draw();
    });
  }

  void destroy() {
    // TODO: Do a better job of cleaning up buffers
    drawing = false;
    canvas = null;
    resizeObserver.disconnect();
  }
}