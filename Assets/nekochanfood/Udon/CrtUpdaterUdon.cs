using UdonSharp;
using UnityEngine;

// Updates a CustomRenderTexture (e.g. CoverRailHistory, update mode = OnDemand) from Udon.
// Place it in the world and assign the texture; works in VRChat builds and in ClientSim.
[UdonBehaviourSyncMode(BehaviourSyncMode.None)]
public class CrtUpdaterUdon : UdonSharpBehaviour
{
    public CustomRenderTexture targetTexture;
    public int updateCount = 1;
    public float updatePeriod = 0f;

    float _time;

    void Start()
    {
        targetTexture.Initialize();
    }

    void Update()
    {
        if (updatePeriod > 0f)
        {
            _time += Time.deltaTime;
            if (_time < updatePeriod) return;
            _time %= updatePeriod;
        }
        targetTexture.Update(updateCount);
    }
}
