using NUnit.Framework;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.SceneManagement;

namespace nekochanfood.CoverRail.Tests
{
    // CoverRail.shader を、プレビューシーンに置いた四角形のパネル（Quad）へ描いて確かめる
    // 正射影のカメラでパネルをちょうど画面いっぱいに写すので、画素の位置 = パネルの UV になる
    // シェーダーはカメラの位置からパネルの奥へレイを飛ばすので、正射影でも見ている人の位置から見た 3D の絵になる
    // 見ている人の位置はパネルから見た座標（x 右、y 上、z 手前への距離）で決め、投影をずらしてパネルの写り方は変えない
    public class CoverRailShaderTests
    {
        const string Folder = "Assets/nekochanfood/Shaders/CoverRail/";
        const int Height = 180;
        // 白いカバーで、中央のカバー（明るさ 1）と、脇（0.75）・映り込み（0.35 以下）・背景（0）を分けるしきい値
        const float CoverThreshold = 0.9f;

        Scene scene;
        Camera camera;
        GameObject panel;
        Material material;
        Texture2D indexAtlas;
        Texture2D history;

        [SetUp]
        public void SetUp()
        {
            scene = EditorSceneManager.NewPreviewScene();
            // シェーダーの既定値で作る（エディタでマテリアルを調整中でも結果が変わらないように）
            material = new Material(AssetDatabase.LoadAssetAtPath<Shader>(Folder + "CoverRail.shader"));
            material.SetTexture("_Atlas", AssetDatabase.LoadAssetAtPath<Texture2D>(Folder + "CoverRailAtlas.png"));
            // 履歴なし（アニメーションなしで今の位置に合わせる）から始める
            material.SetTexture("_History", Texture2D.blackTexture);
            // 端のフェードは、確かめるテストでだけ入れる
            material.SetFloat("_EdgeFade", 0);

            panel = GameObject.CreatePrimitive(PrimitiveType.Quad);
            Object.DestroyImmediate(panel.GetComponent<Collider>());
            panel.GetComponent<MeshRenderer>().sharedMaterial = material;
            SceneManager.MoveGameObjectToScene(panel, scene);

            var cameraObject = new GameObject("Camera");
            SceneManager.MoveGameObjectToScene(cameraObject, scene);
            camera = cameraObject.AddComponent<Camera>();
            camera.enabled = false;
            camera.scene = scene;
            camera.clearFlags = CameraClearFlags.SolidColor;
            camera.backgroundColor = Color.magenta;
        }

        [TearDown]
        public void TearDown()
        {
            Object.DestroyImmediate(material);
            if (indexAtlas) Object.DestroyImmediate(indexAtlas);
            if (history) Object.DestroyImmediate(history);
            EditorSceneManager.ClosePreviewScene(scene);
        }

        [Test]
        public void ShadersCompileWithoutErrors()
        {
            foreach (var name in new[] { "CoverRail.shader", "CoverRailHistory.shader" })
            {
                var shader = AssetDatabase.LoadAssetAtPath<Shader>(Folder + name);
                Assert.IsNotNull(shader, name);
                Assert.IsFalse(ShaderUtil.ShaderHasError(shader), name);
                Assert.IsTrue(shader.isSupported, name);
            }
            var crt = AssetDatabase.LoadAssetAtPath<CustomRenderTexture>(Folder + "CoverRailHistory.asset");
            Assert.AreEqual(crt, AssetDatabase.LoadAssetAtPath<Material>(Folder + "CoverRail.mat").GetTexture("_History"));
            Assert.AreEqual(CustomRenderTextureUpdateMode.OnDemand, crt.initializationMode);
            Assert.AreEqual(CustomRenderTextureUpdateMode.OnDemand, crt.updateMode);
            Assert.IsTrue(crt.doubleBuffered);
        }

        // 中央のカバーは、パネルの大きさ・縦横比によらず、パネルの上下左右の中央に来る
        [TestCase(1.7778f, 1f)]
        [TestCase(3.5556f, 2f)]
        [TestCase(4f, 1f)]
        [TestCase(1f, 1f)]
        [TestCase(0.6f, 1f)]
        public void CenterCoverIsCenteredOnPanel(float width, float height)
        {
            UseWhiteCovers();
            var size = new Vector2(width, height);
            var cover = MeasureCenterCover(Render(size, new Vector3(0, 0, 1.5f * height)));
            Assert.That(Mathf.Abs(cover.left - cover.right), Is.LessThanOrEqualTo(2), $"horizontal {cover.left} / {cover.right}");
            Assert.That(Mathf.Abs(cover.down - cover.up), Is.LessThanOrEqualTo(2), $"vertical {cover.down} / {cover.up}");
            // カバーは正方形
            Assert.That(Mathf.Abs((cover.left + cover.right) - (cover.down + cover.up)), Is.LessThanOrEqualTo(3));
        }

        // パネルと見ている人の距離を同じ割合で大きくすると、同じ絵になる
        [Test]
        public void PanelSizeDoesNotChangeFraming()
        {
            var small = Render(new Vector2(1.7778f, 1f), new Vector3(0, 0, 1.5f));
            var large = Render(new Vector2(3.5556f, 2f), new Vector3(0, 0, 3f));
            Assert.That(MeanDifference(small, large), Is.LessThan(0.01f));
        }

        // 3D の窓: 見る位置を変えると、奥にあるカバーの見え方（視差）が変わる
        [Test]
        public void ViewChangesWithViewerPositionLikeAWindow()
        {
            UseWhiteCovers();
            var size = new Vector2(1.7778f, 1f);
            var front = MeasureCenterCover(Render(size, new Vector3(0, 0, 1.5f)));
            var near = MeasureCenterCover(Render(size, new Vector3(0, 0, 0.8f)));
            // 近づくと、奥にあるカバーは窓（パネル）の中で小さく見える（窓の向こうの景色が広く見える）
            Assert.That(near.down + near.up, Is.LessThan(front.down + front.up - 4));
            // 上から見ると、奥のカバーは窓の中で上へずれる（視線が窓を通る点は、目と奥の物の間にある）
            var above = MeasureCenterCover(Render(size, new Vector3(0, 0.12f, 1.5f)));
            Assert.That(above.up, Is.GreaterThan(above.down + 2));
        }

        // 2D 投影: 固定の仮想カメラの絵なので、見る位置（縦・奥行き）で絵は変わらず、中央のカバーはパネルの中央にある
        [Test]
        public void Projection2DIgnoresViewerParallax()
        {
            material.SetFloat("_Projection2D", 1);
            var size = new Vector2(1.7778f, 1f);
            var front = Render(size, new Vector3(0, 0, 1.5f));
            Assert.That(MeanDifference(front, Render(size, new Vector3(0, 0.3f, 0.8f))), Is.LessThan(1e-4f));

            UseWhiteCovers();
            var cover = MeasureCenterCover(Render(size, new Vector3(0, 0.3f, 0.8f)));
            Assert.That(Mathf.Abs(cover.left - cover.right), Is.LessThanOrEqualTo(2), "horizontal");
            Assert.That(Mathf.Abs(cover.down - cover.up), Is.LessThanOrEqualTo(2), "vertical");
        }

        // 2D 投影 + 追従: 仮想のカメラも付いてくるので、端でも中央のカバーは見ている人の正面に、正面向きで（左右対称に）見える
        [Test]
        public void Projection2DFollowKeepsActiveCoverFrontal()
        {
            UseWhiteCovers();
            material.SetFloat("_Projection2D", 1);
            material.SetFloat("_Follow", 1);
            var size = new Vector2(1.7778f, 1f);
            var viewer = new Vector3(3 * StepFor(size), 0, 1.5f);
            var image = Render(size, viewer);
            int width = WidthFor(size);
            int x = Mathf.RoundToInt((0.5f + viewer.x / size.x) * width);
            int y = Height / 2;
            Assert.That(Brightness(image[y * width + x]), Is.GreaterThan(CoverThreshold), "the active cover is in front of the viewer");
            int left = Run(image, width, x, y, -1, 0), right = Run(image, width, x, y, 1, 0);
            int down = Run(image, width, x, y, 0, -1), up = Run(image, width, x, y, 0, 1);
            Assert.That(Mathf.Abs(left - right), Is.LessThanOrEqualTo(2), $"horizontal {left} / {right}");
            Assert.That(Mathf.Abs(down - up), Is.LessThanOrEqualTo(2), $"vertical {down} / {up}");
        }

        // 追従: 1 枚ずつ進めても、脇に積まれたカバーはワールドで止まっている（行ったり来たりしない）
        // 遠くから見て視差をほぼなくし、左側（ずっと脇にあるカバーだけが写る範囲）を比べる
        [Test]
        public void FollowModeKeepsSideCoversStillInWorld()
        {
            material.SetFloat("_Follow", 1);
            var size = new Vector2(1.7778f, 1f);
            float step = StepFor(size);
            var two = Render(size, new Vector3(2 * step, 0, 500));
            var three = Render(size, new Vector3(3 * step, 0, 500));
            int width = WidthFor(size);
            double sum = 0;
            int count = 0;
            for (int y = 0; y < Height; y++)
                for (int x = 0; x < width / 4; x++)
                {
                    sum += ColorDifference(two[y * width + x], three[y * width + x]);
                    count++;
                }
            Assert.That(sum / count, Is.LessThan(0.01));
        }

        // 左右の端は背景色へ溶け、端から離れたところは変わらない
        [Test]
        public void EdgeFadeBlendsSidesToBackground()
        {
            var size = new Vector2(1.7778f, 1f);
            var viewer = new Vector3(0, 0, 1.5f);
            var plain = Render(size, viewer);
            float fadeWidth = 0.25f;
            material.SetFloat("_EdgeFade", fadeWidth);
            var faded = Render(size, viewer);
            int width = WidthFor(size);
            for (int y = 0; y < Height; y++)
            {
                Assert.That(Brightness(faded[y * width]), Is.LessThan(0.02f), "left edge");
                Assert.That(Brightness(faded[y * width + width - 1]), Is.LessThan(0.02f), "right edge");
            }
            // 端から fadeWidth（パネルの短い辺が 1）より内側は同じ
            int inside = Mathf.CeilToInt(fadeWidth * Height) + 1;
            for (int y = 0; y < Height; y++)
                for (int x = inside; x < width - inside; x++)
                    Assert.That(ColorDifference(plain[y * width + x], faded[y * width + x]), Is.LessThan(1e-4f));
        }

        // 床より下から見上げても、カバーの下に映り込みが見える
        [Test]
        public void ReflectionVisibleFromBelowFloor()
        {
            UseWhiteCovers();
            var size = new Vector2(1.7778f, 1f);
            // パネルの中心より 0.45 下（シーンの床 y = 0 は中心より 0.5 × カバーの幅 ≒ 0.275 下）
            var image = Render(size, new Vector3(0, -0.45f, 0.6f));
            int width = WidthFor(size);
            var cover = MeasureCenterCover(image);
            float reflection = Brightness(image[(Height / 2 - cover.down - 4) * width + width / 2]);
            Assert.That(reflection, Is.InRange(0.1f, 0.5f), "reflection");
        }

        // カバーの下には映り込みがあり、上は背景
        [Test]
        public void ReflectionAppearsBelowCover()
        {
            UseWhiteCovers();
            var size = new Vector2(1.7778f, 1f);
            var image = Render(size, new Vector3(0, 0, 1.5f));
            int width = WidthFor(size);
            var cover = MeasureCenterCover(image);
            int x = width / 2, y = Height / 2;
            float reflection = Brightness(image[(y - cover.down - 4) * width + x]);
            float above = Brightness(image[(Height - 2) * width + x]);
            Assert.That(reflection, Is.InRange(0.1f, 0.5f), "reflection");
            Assert.That(above, Is.LessThan(0.02f), "background above the cover");
        }

        // スクロールは、パネルの横の向きの移動だけで決まる（縦・奥行きの移動では変わらない）
        // パネルの向きはメッシュのトランスフォームに従う（前方が ±X のパネルでは、ワールドの ±Z の移動でスクロールする）
        [TestCase(0f)]
        [TestCase(90f)]
        [TestCase(-135f)]
        public void ScrollFollowsHorizontalMoveAlongPanel(float yaw)
        {
            UseIndexCovers();
            panel.transform.rotation = Quaternion.Euler(0, yaw, 0);
            var size = new Vector2(1.7778f, 1f);
            float step = StepFor(size);
            var still = CenterColor(size, new Vector3(0, 0, 1.5f));
            Assert.That(ColorDifference(still, CenterColor(size, new Vector3(0, 0.3f, 2.5f))), Is.LessThan(1e-4f), "vertical / depth");
            Assert.That(ColorDifference(still, CenterColor(size, new Vector3(0.3f * step, 0, 1.5f))), Is.LessThan(1e-4f), "within one cover");

            var moved = CenterColor(size, new Vector3(step, 0, 1.5f));
            Assert.That(ColorDifference(still, moved), Is.GreaterThan(1e-3f), "moved");
            material.SetFloat("_ScrollOffset", 1);
            Assert.That(ColorDifference(moved, CenterColor(size, new Vector3(0, 0, 1.5f))), Is.LessThan(1e-4f), "one cover");
        }

        // 追従モード: 中央のカバーが見ている人の正面に来る（定点モードでパネルの中心に来るのと同じカバー）
        [Test]
        public void FollowModeMovesActiveCoverInFrontOfViewer()
        {
            UseIndexCovers();
            var size = new Vector2(1.7778f, 1f);
            var viewer = new Vector3(2 * StepFor(size), 0, 1.5f);
            var active = CenterColor(size, viewer);

            material.SetFloat("_Follow", 1);
            var image = Render(size, viewer);
            int width = WidthFor(size);
            int x = Mathf.RoundToInt((0.5f + viewer.x / size.x) * width);
            var inFront = image[(Height / 2) * width + x];
            Assert.That(ColorDifference(active, inFront), Is.LessThan(1e-4f), "the active cover is in front of the viewer");
            Assert.That(ColorDifference(active, image[(Height / 2) * width + width / 2]), Is.GreaterThan(1e-3f), "not at the panel center");
        }

        // 1 枚進むのに必要な移動はカバーの大きさで決まり、パネルを横に伸ばしても鈍くならない
        [Test]
        public void StretchingPanelKeepsScrollResponse()
        {
            UseIndexCovers();
            var normal = new Vector2(1.7778f, 1f);
            var wide = new Vector2(5f, 1f);
            Assert.AreEqual(StepFor(normal), StepFor(wide));
            float step = StepFor(normal);
            for (int covers = 1; covers <= 3; covers++)
            {
                var a = CenterColor(normal, new Vector3(covers * step, 0, 1.5f));
                var b = CenterColor(wide, new Vector3(covers * step, 0, 1.5f));
                Assert.That(ColorDifference(a, b), Is.LessThan(1e-4f), $"{covers} covers");
            }
        }

        // 履歴（見ている人の位置の記録）で、目標のカバーが変わってから _ScrollDuration 秒（0.75 秒）かけて power4.out で動く
        [TestCase(0.1f)]
        [TestCase(0.25f)]
        [TestCase(1f)]
        public void HistoryAnimatesScrollWithPower4Out(float secondsSinceMove)
        {
            var size = new Vector2(1.7778f, 1f);
            var viewer = new Vector3(0, 0, 1.5f);
            // 見ている人は、secondsSinceMove 秒前にパネルの前から 1 枚分右へ動いた
            float now = CurrentShaderTime();
            var before = ViewerWorld(new Vector3(0, 0, 1.5f));
            var after = ViewerWorld(new Vector3(StepFor(size), 0, 1.5f));
            System.Func<float, Vector3> positionAt = t => t < now - secondsSinceMove ? before : after;
            UseHistory(now, positionAt);
            var animated = Render(size, viewer);

            // 履歴は 1/60 秒ごとの記録なので、動いたと分かるのは「動いた後」の最初の記録の時刻
            float changed = now;
            for (int k = 255; k >= 0; k--)
            {
                float t = now - k / 60f;
                if (positionAt(t) == after)
                {
                    changed = t;
                    break;
                }
            }
            float x = Mathf.Clamp01((now - changed) / material.GetFloat("_ScrollDuration"));
            float expected = 1 - Mathf.Pow(1 - x, 5);
            // 履歴なしで _ScrollOffset を変えた絵と照らし合わせ、いちばん近いスクロールの位置を求める
            // （動き出しは傾きが急なので、履歴の 1 フレームの刻みや時刻のずれの分だけ許す）
            material.SetTexture("_History", Texture2D.blackTexture);
            float best = 0, bestDifference = float.MaxValue;
            for (float s = 0; s <= 1.0001f; s += 0.01f)
            {
                material.SetFloat("_ScrollOffset", s);
                float difference = MeanDifference(animated, Render(size, viewer));
                if (difference < bestDifference)
                {
                    bestDifference = difference;
                    best = s;
                }
            }
            Assert.That(best, Is.EqualTo(expected).Within(0.03f), $"best difference {bestDifference}");
        }

        // 履歴が更新されていなければ（エディタで再生していないときなど）、今の位置にそのまま合わせる
        [Test]
        public void StaleHistoryFallsBackToCurrentViewer()
        {
            var size = new Vector2(1.7778f, 1f);
            var viewer = new Vector3(0, 0, 1.5f);
            float now = CurrentShaderTime();
            var away = ViewerWorld(new Vector3(5 * StepFor(size), 0, 1.5f));
            UseHistory(now - 10, t => away);
            var stale = Render(size, viewer);
            material.SetTexture("_History", Texture2D.blackTexture);
            Assert.That(MeanDifference(stale, Render(size, viewer)), Is.LessThan(1e-4f));
        }

        void UseWhiteCovers()
        {
            material.SetTexture("_Atlas", Texture2D.whiteTexture);
        }

        // セルごとに違う 1 色のアトラス（中央のカバーの色で、どのカバーかが分かる）
        void UseIndexCovers()
        {
            indexAtlas = new Texture2D(8, 8, TextureFormat.RGBAFloat, false, true) { filterMode = FilterMode.Point };
            for (int y = 0; y < 8; y++)
                for (int x = 0; x < 8; x++)
                    indexAtlas.SetPixel(x, y, new Color((x + 1) / 8f, (y + 1) / 8f, 0.5f, 1));
            indexAtlas.Apply();
            material.SetTexture("_Atlas", indexAtlas);
            material.SetFloat("_AtlasCells", 8);
        }

        // 履歴の CRT と同じ並び（x = 0 が今、右へ行くほど古い、1 フレーム 1/60 秒）のテクスチャ
        void UseHistory(float newestTime, System.Func<float, Vector3> positionAt)
        {
            const int count = 256;
            history = new Texture2D(count, 1, TextureFormat.RGBAFloat, false, true) { filterMode = FilterMode.Point };
            for (int k = 0; k < count; k++)
            {
                float t = newestTime - k / 60f;
                var p = positionAt(t);
                history.SetPixel(k, 0, new Color(p.x, p.y, p.z, t));
            }
            history.Apply();
            material.SetTexture("_History", history);
        }

        // Camera.Render したときにシェーダーが受け取る _Time.y
        // エディタでは Time.time とずれることがある（再コンパイルの直後など）ので、_Time.y をそのまま書き出すシェーダーで描いて読む
        const string TimeProbeShader =
            "Shader \"Hidden/CoverRailTimeProbe\" { SubShader { Pass { CGPROGRAM\n" +
            "#pragma vertex vert\n#pragma fragment frag\n#include \"UnityCG.cginc\"\n" +
            "float4 vert(float4 v : POSITION) : SV_POSITION { return UnityObjectToClipPos(v); }\n" +
            "float4 frag() : SV_Target { return _Time.y; }\n" +
            "ENDCG } } }";

        float CurrentShaderTime()
        {
            var shader = ShaderUtil.CreateShaderAsset(TimeProbeShader);
            var probe = new Material(shader);
            var renderer = panel.GetComponent<MeshRenderer>();
            renderer.sharedMaterial = probe;
            var image = Render(new Vector2(1, 1), new Vector3(0, 0, 1));
            renderer.sharedMaterial = material;
            Object.DestroyImmediate(probe);
            Object.DestroyImmediate(shader);
            return image[image.Length / 2].r;
        }

        // 1 枚進むのに必要な横の移動（ワールドの長さ）
        float StepFor(Vector2 size)
        {
            return Mathf.Min(size.x, size.y) * material.GetFloat("_CoverSize") * material.GetFloat("_ScrollStep");
        }

        int WidthFor(Vector2 size)
        {
            return Mathf.RoundToInt(Height * size.x / size.y);
        }

        // パネルから見た位置（x 右、y 上、z 手前への距離）をワールドへ（Quad の表は -z を向く）
        Vector3 ViewerWorld(Vector3 viewer)
        {
            return panel.transform.position + panel.transform.rotation * new Vector3(viewer.x, viewer.y, -viewer.z);
        }

        Color CenterColor(Vector2 size, Vector3 viewer)
        {
            var image = Render(size, viewer);
            int width = WidthFor(size);
            return image[(Height / 2) * width + width / 2];
        }

        Color[] Render(Vector2 size, Vector3 viewer)
        {
            panel.transform.localScale = new Vector3(size.x, size.y, 1);
            camera.transform.SetPositionAndRotation(ViewerWorld(viewer), panel.transform.rotation);
            float hw = size.x * 0.5f, hh = size.y * 0.5f;
            camera.projectionMatrix = Matrix4x4.Ortho(-hw - viewer.x, hw - viewer.x, -hh - viewer.y, hh - viewer.y, 0.01f, Mathf.Max(100, viewer.z * 2));

            int width = WidthFor(size);
            var target = RenderTexture.GetTemporary(width, Height, 24, RenderTextureFormat.ARGBFloat, RenderTextureReadWrite.Linear);
            camera.targetTexture = target;
            camera.Render();
            var previous = RenderTexture.active;
            RenderTexture.active = target;
            var readback = new Texture2D(width, Height, TextureFormat.RGBAFloat, false, true);
            readback.ReadPixels(new Rect(0, 0, width, Height), 0, 0);
            readback.Apply();
            RenderTexture.active = previous;
            camera.targetTexture = null;
            RenderTexture.ReleaseTemporary(target);
            var pixels = readback.GetPixels();
            Object.DestroyImmediate(readback);
            return pixels;
        }

        struct CoverExtent
        {
            public int left, right, down, up;
        }

        // 画面の中心から、中央のカバー（白）が続く画素数を上下左右に数える
        CoverExtent MeasureCenterCover(Color[] image)
        {
            int width = image.Length / Height;
            int cx = width / 2, cy = Height / 2;
            Assert.That(Brightness(image[cy * width + cx]), Is.GreaterThan(CoverThreshold), "the panel center shows the center cover");
            CoverExtent e;
            e.left = Run(image, width, cx, cy, -1, 0);
            e.right = Run(image, width, cx, cy, 1, 0);
            e.down = Run(image, width, cx, cy, 0, -1);
            e.up = Run(image, width, cx, cy, 0, 1);
            return e;
        }

        static int Run(Color[] image, int width, int x, int y, int dx, int dy)
        {
            int n = 0;
            while (true)
            {
                x += dx;
                y += dy;
                if (x < 0 || x >= width || y < 0 || y >= Height) return n;
                if (Brightness(image[y * width + x]) < CoverThreshold) return n;
                n++;
            }
        }

        static float Brightness(Color c)
        {
            return Mathf.Max(c.r, Mathf.Max(c.g, c.b));
        }

        static float ColorDifference(Color a, Color b)
        {
            return Mathf.Abs(a.r - b.r) + Mathf.Abs(a.g - b.g) + Mathf.Abs(a.b - b.b);
        }

        static float MeanDifference(Color[] a, Color[] b)
        {
            Assert.AreEqual(a.Length, b.Length);
            double sum = 0;
            for (int i = 0; i < a.Length; i++)
                sum += ColorDifference(a[i], b[i]);
            return (float)(sum / (a.Length * 3));
        }
    }
}
