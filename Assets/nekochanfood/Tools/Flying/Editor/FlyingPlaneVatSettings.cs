using UnityEditor;
using UnityEngine;

namespace Nekochanfood.Flying
{
    /// <summary>
    /// VAT のベイクの設定
    /// インスペクターで値を変え、右上のメニュー（⋮）の Bake か、Tools > nekochanfood > Bake Flying Plane VAT で反映する
    /// </summary>
    public class FlyingPlaneVatSettings : ScriptableObject
    {
        const string Path = "Assets/nekochanfood/Tools/Flying/FlyingPlaneVatSettings.asset";

        [Header("サブの数")]
        [Tooltip("同時に飛べるサブの数。増やすと出現の頻度が上がるが、レイマーチの負荷も機体 1 機ぶんずつ増える（VAT の横幅も 7 列ずつ広がる）")]
        [Range(0, 8)] public int subCount = 2;

        [Header("サブの出現の頻度")]
        [Tooltip("サブが続けて入るときの、最小の間隔(s)。小さいほど頻繁に入る")]
        [Min(0f)] public float spawnInterval = 5f;

        [Tooltip("サブがステージの外へ出てから、その機体が次に入れるようになるまでの待ち(s)の範囲")]
        [Min(0f)] public float respawnDelayMin = 0f;
        [Min(0f)] public float respawnDelayMax = 1f;

        [Header("サブの流れの速さ")]
        [Tooltip("メインから見て後ろへ流れる速さの倍率。大きいほど早く通り過ぎ、ステージにいる時間が短くなる（同時に飛べる数が限られているので、頻度も上がる）")]
        [Range(0.05f, 1f)] public float followFactor = 0.35f;

        [Tooltip("旋回し終えたときの流れの速さの倍率。旋回が進むにつれて Follow Factor からここまで上げ、曲がった分だけ加速して離れていくように見せる")]
        [Range(0.05f, 1f)] public float turnFollowFactor = 0.8f;

        [Header("サブの見える範囲")]
        [Tooltip("旋回を始めたサブが見えなくなる、メインからの距離（旋回しないサブはステージの半径 12 で見えなくなる）。大きいほど、曲がって遠ざかる様子が長く見える")]
        [Min(12f)] public float turnStageRadius = 28f;

        [ContextMenu("Bake")]
        void Bake() => FlyingPlaneVatBaker.Bake();

        /// <summary>設定のアセットを読む。なければ既定値で作る</summary>
        public static FlyingPlaneVatSettings LoadOrCreate()
        {
            var settings = AssetDatabase.LoadAssetAtPath<FlyingPlaneVatSettings>(Path);
            if (settings != null) return settings;
            settings = CreateInstance<FlyingPlaneVatSettings>();
            AssetDatabase.CreateAsset(settings, Path);
            AssetDatabase.SaveAssets();
            return settings;
        }
    }
}
