import 'dart:html';

import 'package:superflat/gl.dart';
import 'package:superflat/mesh.dart';
import 'package:superflat/modal.dart';
import 'package:superflat/sprite.dart';

class SceneViewer extends Viewer {
  GalleryScene scene;

  SceneViewer(this.scene);

  GLApp app;

  show() async {
    var e = CanvasElement()
      ..id = "modal-image"
      ..style.width = "1024px"
      ..style.height = "768px"
      ..style.backgroundColor = scene.meta.color;

    modal.div.children.add(e);

    app = GLApp(e);
    await app.init();

    var ctx = app.viewport;

    for (var m in scene.models) {
      var uniforms = <String, dynamic>{};
      for (var k in m.uniforms.keys) {
        var v = m.uniforms[k];
        if (v is String) {
          uniforms[k] = await ctx.loadTexture(v);
        } else uniforms[k] = v;
      }

      await app.addObject(
        MeshGLObject(
          await ctx.loadObj(m.obj),
          BasicMaterial(
            await ctx.loadShader(m.vertShader, m.fragShader),
            uniforms: uniforms,
          ),
        )
          ..pos = m.pos
          ..ang = m.ang
          ..scale = m.scale
      );
    }

    await app.addObject(GLFilter(ctx, await ctx.loadShader(
      "/assets/gl/tonemap/vert.glsl",
      "/assets/gl/tonemap/frag.glsl",
    )));

    app.start();

    e.style.opacity = "1";
  }

  void close() {
    app.destroy();
  }
}