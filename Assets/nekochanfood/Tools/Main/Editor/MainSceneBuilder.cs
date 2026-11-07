using UdonSharp;
using UdonSharpEditor;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using VRC.SDK3.Components;

namespace nekochanfood.Tools
{
    /// Rebuilds Assets/main.unity: a minimal VRChat world that shows every shader in this repo.
    public static class MainSceneBuilder
    {
        const string Shaders = "Assets/nekochanfood/Shaders/";

        [MenuItem("Tools/nekochanfood/Build Main Scene")]
        public static void Build()
        {
            var scene = EditorSceneManager.NewScene(NewSceneSetup.DefaultGameObjects, NewSceneMode.Single);

            var floor = GameObject.CreatePrimitive(PrimitiveType.Plane);
            floor.name = "Floor";
            floor.transform.localScale = new Vector3(2, 1, 2);

            var spawn = new GameObject("Spawn").transform;
            spawn.position = new Vector3(0, 0, -4);
            var world = new GameObject("VRCWorld");
            world.AddComponent<VRCSceneDescriptor>().spawns = new[] { spawn };

            Panel("CoverRail", Shaders + "CoverRail/CoverRail.mat", new Vector3(-2.2f, 1.5f, 2), 4, 2);
            Panel("FlyingPlane", Shaders + "Flying/FlyingPlane.mat", new Vector3(2.2f, 1.5f, 2), 4, 2);
            Panel("FlyingPlane_Dark", Shaders + "Flying/FlyingPlane_Dark.mat", new Vector3(6.6f, 1.5f, 2), 4, 2);

            // A fresh checkout has no compiled U# program yet (batch mode too): create and compile it first.
            const string Prog = "Assets/nekochanfood/Udon/CrtUpdaterUdon.asset";
            if (UdonSharpEditorUtility.GetUdonSharpProgramAsset(typeof(CrtUpdaterUdon)) == null)
            {
                var asset = ScriptableObject.CreateInstance<UdonSharpProgramAsset>();
                asset.sourceCsScript = AssetDatabase.LoadAssetAtPath<MonoScript>("Assets/nekochanfood/Udon/CrtUpdaterUdon.cs");
                AssetDatabase.CreateAsset(asset, Prog);
                UdonSharpProgramAsset.CompileAllCsPrograms(true);
                AssetDatabase.SaveAssets();
            }

            // CoverRailHistory is OnDemand: something has to update it.
            var updater = new GameObject("CoverRailHistoryUpdater");
            var behaviour = UdonSharpUndo.AddComponent<CrtUpdaterUdon>(updater);
            behaviour.targetTexture = AssetDatabase.LoadAssetAtPath<CustomRenderTexture>(Shaders + "CoverRail/CoverRailHistory.asset");
            UdonSharpEditorUtility.CopyProxyToUdon(behaviour);

            EditorSceneManager.SaveScene(scene, "Assets/main.unity");
            EditorBuildSettings.scenes = new[] { new EditorBuildSettingsScene("Assets/main.unity", true) };
        }

        static void Panel(string name, string material, Vector3 pos, float w, float h)
        {
            var q = GameObject.CreatePrimitive(PrimitiveType.Quad);
            q.name = name;
            q.transform.position = pos;
            q.transform.localScale = new Vector3(w, h, 1);
            q.GetComponent<MeshRenderer>().sharedMaterial = AssetDatabase.LoadAssetAtPath<Material>(material);
        }
    }
}
