using UnityEngine;

namespace Grass.Scripts
{
    [ExecuteInEditMode]
    public class GrassTrample : MonoBehaviour
    {
        [SerializeField] private Material material;
        [SerializeField] [Range(0, 10)] private float radius;
        [SerializeField] [Range(-2, 5)] private float heightOffset;

        private Transform cachedTransform;
        private readonly int grassTrampleProperty = Shader.PropertyToID("_Trample");

        private void Awake()
        {
            cachedTransform = transform;
        }

        private void Update()
        {
            if (material == null)
            {
                return;
            }

            var position = cachedTransform.position;
            material.SetVector(grassTrampleProperty, new Vector4(position.x, position.y + heightOffset, position.z, radius));
        }
    }
}