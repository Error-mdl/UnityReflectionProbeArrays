using System;
using System.Collections;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text.RegularExpressions;
using System.IO;
using UnityEngine;
using UnityEditor;
using UnityEngine.SceneManagement;
using UnityEditor.SceneManagement;
using Extensions;

public class ReflectionProbeArrayCreator : EditorWindow
{
  #region Global Variables

  private static int AreUV23Compressed;
  private static bool isWorkingCopy;

  private const int MAXPROBES = 4;
  private const int WINDOW_MIN_W = 480;
  private const int WINDOW_MIN_H = 240;
  private const int WINDOW_BORDER = 4;
  private const int WINDOW_ELEMENT_SPACING = 4;
  private const int WARNING_ICON_SIZE = 32;
  private const int BUTTON_WIDTH = 64;
  private const string WORKING_COPY_SUFFIX = "_workingcopy";



  #endregion

  #region Structs
  struct ProbeDistance
  {
    public int probeIndex;
    public float probeDistance;
  }

  struct ProbeOverlap
  {
    public int probeIndex;
    public float VolumeOverlap;
  }

  struct MeshProbes
  {
    public int[] probeIndex;
    public float[] probeWeight;
  }

  #endregion

  #region UI Functions

  [MenuItem("Window/Reflection Probe Arrays")]
  public static void ShowWindow()
  {
    ReflectionProbeArrayCreator RPAWindow = GetWindow<ReflectionProbeArrayCreator>(true, "Convert Reflection Probes to Array", true);
    RPAWindow.minSize = new Vector2(WINDOW_MIN_W, WINDOW_MIN_H);
  }

  public void Awake()
  {
    SerializedObject projSettings = GetProjectSettingsAsset();
    if (projSettings != null)
    {
      AreUV23Compressed = CheckIfUV23Compressed(projSettings) ? 1 : 0;
    }
    else
    {
      AreUV23Compressed = -1;
    }
    CheckIfWorkingCopy(SceneManager.GetActiveScene(), OpenSceneMode.Single);
    EditorSceneManager.sceneOpened += CheckIfWorkingCopy;
  }

  public void OnDestroy()
  {
    EditorSceneManager.sceneOpened -= CheckIfWorkingCopy;
  }

  void OnGUI()
  {
    if (AreUV23Compressed == 1)
    {
      DrawVertexCompressionWarning();
    }
    else if (AreUV23Compressed == -1)
    {
      EditorGUILayout.BeginHorizontal();
      EditorGUILayout.HelpBox("Could not find the project settings asset. Make sure you have vertex compression turned off for" +
        "texcoords 2 and 3 in Project Settings -> Player -> Other Settings", MessageType.Warning);
      EditorGUILayout.EndHorizontal();
    }

    EditorGUILayout.HelpBox("It is strongly recommended that you do not use this on the main working copy of your scene. Rather, before you intend to build the project save a duplicate of the scene and run it on the duplicate." +
      "This tool duplicates, modifies, and replaces the mesh of every static batched object in the scene. Thus any changes to the source model files will not update the objects in the scene. Additionally, it is " +
      "recommended that you unpack all models/prefabs containing static batched meshes in the scene copy so that when building a package unity does not also include the original model files referenced by the prefab." +
      "To prevent accidentally ruining your main copy of the scene, you can add \"_workingcopy\" to the end of the scene name and this tool will refuse to run on it.", MessageType.Warning);

    if (isWorkingCopy)
    {
      EditorGUILayout.HelpBox("This is your working copy, you cannot run the tool on this scene. Save a duplicate scene that does not end with \"_workingcopy\", and run the tool on that.", MessageType.Error);
    }

    GUILayout.FlexibleSpace();
    using (new EditorGUI.DisabledScope(isWorkingCopy))
    {
      if (GUILayout.Button("Create Arrays and Convert All Static Batched Meshes", GUILayout.Width(EditorGUIUtility.currentViewWidth - 2 * WINDOW_BORDER), GUILayout.Height(30)))
      {
        ConvertToArray();
      }
    }
  }

  /** DrawVertexCompressionWarning
   * 
   *  Draw a warning that the project has texcoords 2 and/or 3 set to be compressed, and present the the user with a button to turn compression off
   * 
   */
  void DrawVertexCompressionWarning()
  {
    Rect warningBox = EditorGUILayout.BeginHorizontal();
    string warningMessage = "Texcoords 2 and 3 are set to be compressed in your project's vertex compresssion settings. This will break reflection probes on static batched meshes.";
    EditorGUILayout.HelpBox(warningMessage, MessageType.Error);

    /* All this garbage is necessary because you can't get the size of the warning box, so you have to manually calculate what
       the size of the warning box should be based on the window size and what is in it to make the "Fix" button have the same height */
    Texture2D dummyImg = new Texture2D(WARNING_ICON_SIZE, WARNING_ICON_SIZE);
    GUIContent dummyCont1 = new GUIContent(warningMessage);
    GUIContent dummyCont2 = new GUIContent(dummyImg);
    float contentWidth1 = EditorGUIUtility.currentViewWidth - 2 * WINDOW_BORDER - WINDOW_ELEMENT_SPACING - BUTTON_WIDTH - WARNING_ICON_SIZE;
    float contentWidth2 = EditorGUIUtility.currentViewWidth - 2 * WINDOW_BORDER - WINDOW_ELEMENT_SPACING - BUTTON_WIDTH;
    float contentHeight1 = EditorStyles.helpBox.CalcHeight(dummyCont1, contentWidth1);
    float contentHeight2 = EditorStyles.helpBox.CalcHeight(dummyCont2, contentWidth2);


    float contentHeight = Mathf.Max(contentHeight1, contentHeight2);
    if (GUILayout.Button("Fix", GUILayout.Width(BUTTON_WIDTH), GUILayout.Height(contentHeight)))
    {
      SerializedObject projSettings = GetProjectSettingsAsset();
      DisableUV34CompressionFlags(projSettings);
      AreUV23Compressed = CheckIfUV23Compressed(projSettings) ? 1 : 0;
    }
    EditorGUILayout.EndHorizontal();
  }

  public static void CheckIfWorkingCopy(Scene arg1, OpenSceneMode mode)
  {
    string sceneName = arg1.name;
    sceneName = sceneName.ToLower();
    if (sceneName.Length >= WORKING_COPY_SUFFIX.Length)
    {
      isWorkingCopy = sceneName.EndsWith(WORKING_COPY_SUFFIX);
    }
    else
    {
      isWorkingCopy = false;
    }
  }

  #endregion

  #region Project Settings

  /** GetProjectSettingsAsset
   * 
   *  Unity doesn't provide any method for setting the project's vertex channel compression flags, so we're forced to directly open the
   *  project settings configuration file and read and write to it directly. This is probably really bad, but it's the only option.
   * 
   */
  SerializedObject GetProjectSettingsAsset()
  {
    const string projectSettingsAssetPath = "ProjectSettings/ProjectSettings.asset";
    UnityEngine.Object projSettingsObj = AssetDatabase.LoadMainAssetAtPath(projectSettingsAssetPath);
    if (projSettingsObj == null)
    {
      return null;
    }
    else
    {
      SerializedObject projectSettings = new SerializedObject(AssetDatabase.LoadMainAssetAtPath(projectSettingsAssetPath));
      return projectSettings;
    }
  }

  /** DisableUV23CompressionFlags
   * 
   *  Disable vertex compression on TEXCOORD2 and 3 in the given project settings asset.
   *  
   *  We're storing the indicies of the four reflection probes for each mesh as four 16-bit ushorts in the bits of TEXCOORD2 32-bit floating
   *  point x and y channels. The z and w channels as well as all of TEXCOORD3 (UV4) is storing worldspace coordinates of mesh bounding boxes.
   *  If compression is enabled in these channels, it will reduce the values to half precision complety destroying the ushorts and making the
   *  bounding boxes suffer from extreme precision errors only moderately far from origin. Thus we must turn off vertex compression for these
   *  channels.
   *
   */
  void DisableUV34CompressionFlags(SerializedObject projectSettings)
  {
    SerializedProperty VertexMask = projectSettings.FindProperty("VertexChannelCompressionMask");
    int flagValue = VertexMask.intValue;
    VertexMask.intValue = (flagValue & (~((int)VertexChannelCompressionFlags.TexCoord2))) & (~((int)VertexChannelCompressionFlags.TexCoord3));
    projectSettings.ApplyModifiedProperties();
  }

  /** CheckIfUV23Compressed
   * 
   *  Check if Texcoords 2 and 3 are set to be compressed to 16 bit values in the project settings
   * 
   */
  bool CheckIfUV23Compressed(SerializedObject projectSettings)
  {
    SerializedProperty VertexMask = projectSettings.FindProperty("VertexChannelCompressionMask");
    int compFlags = VertexMask.intValue;
    return ((compFlags & (int)VertexChannelCompressionFlags.TexCoord2) != 0) || ((compFlags & (int)VertexChannelCompressionFlags.TexCoord3) != 0);
  }


  #endregion

  
  /** ConvertToArray
   * 
   *  First, go through every gameobject in the scene and find all reflection probe components and assemble them into a list.
   *  Then create a cubemap array out of the probe's textures, and a 2D texture array containing each probe's position and bounds.
   *  Finally, go through every gameobject in the scene, find all mesh filters on static batching game objects, find the closest
   *  4 probes to each object, duplicate the mesh referenced by each and add the probe indicies and mesh bounds to texcoord2 and 3,
   *  assign each mesh to the corresponding mesh filter and mesh collider, and assign the reflection probe cubemap array and settings
   *  2D array to the first material
   * 
   */
  private void ConvertToArray()
  {
    List<ReflectionProbe> probeList = GetProbeComponentList();
    if (probeList.Count == 0)
    {
      Debug.LogError("No Reflection Probes in Scene");
      return;
    }

    CubemapArray reflTexArray = CreateProbeTexArray(probeList);
    if (reflTexArray == null)
    {
      return;
    }

    Texture2DArray settingsArray = CreateProbeSettingsArray(probeList);

    ConvertSceneMeshes(probeList, reflTexArray, settingsArray);
  }

  #region Texture Array Functions

  /** GetProbeList
   * 
   * Compile a list of every active probe in the scene and return it
   * 
   */
  private List<ReflectionProbe> GetProbeComponentList()
  {
    List<ReflectionProbe> probeList = new List<ReflectionProbe>();
    GameObject[] allObj = UnityEngine.Object.FindObjectsOfType<GameObject>();

    for (int i = 0; i < allObj.Length; i++)
    {
      ReflectionProbe tempProbe = allObj[i].GetComponent(typeof(ReflectionProbe)) as ReflectionProbe;
      if (tempProbe != null && allObj[i].activeInHierarchy)
      {
        probeList.Add(tempProbe);
      }
    }
    return probeList;
  }



  /** CreateProbeTexArray
   * 
   *  Given a list of probes, assemble a new CubemapArray out of them and return it.
   *
   */
  private CubemapArray CreateProbeTexArray(List<ReflectionProbe> probeArray)
  {
    int reflProbeArrayDim = probeArray[0].bakedTexture.width;
    TextureFormat reflProbeFormat = (probeArray[0].bakedTexture as Cubemap).format; //Have to cast the probe's texture to a cubemap because it is given as a generic texture for some reason
    CubemapArray reflTexArray = new CubemapArray(reflProbeArrayDim, probeArray.Count, reflProbeFormat, true);
    for (int i = 0; i < probeArray.Count; i++)
    {
      //Sanity check to make sure that all probes have the same texture format. We can't copy cubemaps of different texture formats into the same array
      if ((probeArray[i].bakedTexture as Cubemap).format != reflProbeFormat)
      {
        string errormessage = String.Format("{0}'s cubemap has format {1}, while {2}'s cubemap has format {3}. All probes must have the same texture format. Make sure all probes have the same HDR setting.",
          probeArray[0].gameObject.name, (probeArray[0].bakedTexture as Cubemap).format, probeArray[i].gameObject.name, (probeArray[i].bakedTexture as Cubemap).format);
        Debug.LogError(errormessage);
        EditorUtility.DisplayDialog("Inconsistent Probe Textures", errormessage, "Close");
        return null;
      }

      //Sanity check to make sure that all probes have the same dimensions. We can't copy cubemaps of different sizes into the same array
      if (probeArray[i].bakedTexture.width != reflProbeArrayDim)
      {
        string errormessage = String.Format("{0} is {1}x{1}, while {2} is {3}x{3}. All probes must have the same resolution. Make sure to rebake your probes after changing the resolution!",
          probeArray[0].gameObject.name, probeArray[0].bakedTexture.width, probeArray[i].gameObject.name, probeArray[i].bakedTexture.width);
        Debug.LogError(errormessage);
        EditorUtility.DisplayDialog("Inconsistent Probe Textures", errormessage, "Close");
        return null;
      }

      // Copy each reflection probe's cubemap into the array
      // Note that cubemap arrays are treated as a normal texture array, just with every successive group of 6 images in the array being the sides of one cubemap
      for (int mip = 0; mip < probeArray[0].bakedTexture.mipmapCount; mip++)
      {
        for (int side = 0; side < 6; side++)
        {
          Graphics.CopyTexture(probeArray[i].bakedTexture, side, mip, reflTexArray, (i * 6) + side, mip);
        }
      }
    }
    //Save the cubemap array to the same directory as the reflection probes
    string path = Path.GetDirectoryName(AssetDatabase.GetAssetPath(probeArray[0].bakedTexture)) + "\\" + "ReflectionProbeArray.asset";

    //Check to see if a cubemap array already exists at the path, if so replace its data with our array instead of overwriting it so materials don't lose the reference to the array.
    CubemapArray tempArray = AssetDatabase.LoadAssetAtPath(path, typeof(CubemapArray)) as CubemapArray;
    if (tempArray != null)
    {
      EditorUtility.CopySerialized(reflTexArray, tempArray);
      reflTexArray = tempArray;
    }
    else
    {
      AssetDatabase.CreateAsset(reflTexArray, path);
    }
    return reflTexArray;
  }

  /** CreateProbeSettingsArray
   *  
   *  Generate a texture array of 4x1 images storing information about each probe in the corresponding image.
   *  The first pixel contains the worldspace center of the probe in the rgb channels and the box projection bool
   *  in the alpha channel. The second contains the minimum corner of the probes bounding box, and the third contains
   *  the maximum corner. The fourth pixel is blank.
   *  
   */
  private Texture2DArray CreateProbeSettingsArray(List<ReflectionProbe> probeList)
  {
    int width = 4;
    int height = 1;
    Texture2DArray settingsTexArray = new Texture2DArray(width, height, probeList.Count, TextureFormat.RGBAFloat, false);
    for (int i = 0; i < probeList.Count; i++)
    {
      Color[] settings = new Color[width];
      settings[0] = (Vector4)(probeList[i].gameObject.transform.position);
      settings[0].a = probeList[i].boxProjection ? 1.0f : 0.0f;
      settings[1] = new Vector4(probeList[i].bounds.min.x, probeList[i].bounds.min.y, probeList[i].bounds.min.z, 0.0f);
      settings[2] = new Vector4(probeList[i].bounds.max.x, probeList[i].bounds.max.y, probeList[i].bounds.max.z, 0.0f);
      settings[3] = Vector4.zero;

      settingsTexArray.SetPixels(settings, i, 0);
    }
    settingsTexArray.Apply(false);

    string path = Path.GetDirectoryName(AssetDatabase.GetAssetPath(probeList[0].bakedTexture)) + "\\" + "ReflectionProbeSettings.asset";
    Texture2DArray tempArray = AssetDatabase.LoadAssetAtPath(path, typeof(Texture2DArray)) as Texture2DArray;
    if (tempArray != null)
    {
      EditorUtility.CopySerialized(settingsTexArray, tempArray);
      settingsTexArray = tempArray;
    }
    else
    {
      AssetDatabase.CreateAsset(settingsTexArray, path);
    }

    return settingsTexArray;
  }

  #endregion

  #region Mesh Conversion Functions

  /** ConvertSceneMeshes
   * 
   *  Finds all game objects with a mesh filter and static batching set in the scene, then
   *  finds the closest reflection probes to each mesh and assigns a weight to each one
   *  based on the overlapping volume of the mesh's bounding box with the probes bounds.
   *  Then it duplicates each object's mesh data, adds new UV channels to store the indicies
   *  and weights of the reflection probes effecting the object, saves it as a new mesh,
   *  and assigns the new mesh to the gameobject's mesh filter and (if present) mesh collider.
   *  
   */
  private void ConvertSceneMeshes(List<ReflectionProbe> reflProbeList, CubemapArray reflProbeTexArray, Texture2DArray reflProbeSettingsArray)
  {
    GameObject[] sceneRoot = SceneManager.GetActiveScene().GetRootGameObjects();
    if (sceneRoot == null)
    {
      Debug.LogError("No Game Objects to Convert");
      return;
    }
    List<GameObject> objectsToConvert = new List<GameObject>();
    foreach (GameObject rootObj in sceneRoot)
    {
      FindAllStaticMeshes(rootObj, ref objectsToConvert);
    }
    
    int meshNum = 0;
    foreach (GameObject gObj in objectsToConvert)
    {
      meshNum++;
      EditorUtility.DisplayProgressBar(String.Format("Converting {0}/{1}", gObj.transform.parent.name, gObj.name), String.Format("{0} of {1}", meshNum, objectsToConvert.Count), ((float) meshNum) / ((float) objectsToConvert.Count));
      MeshProbes closestProbes = FindClosestProbes(reflProbeList, gObj);
      Mesh newMesh = MakeMeshCopy(gObj, closestProbes);
      gObj.GetComponent<MeshFilter>().sharedMesh = newMesh;
      MeshCollider gObjCol = gObj.GetComponent<MeshCollider>();    
      if (gObjCol != null)
      {
        gObjCol.sharedMesh = newMesh;
      }
      MeshRenderer gObjRender = gObj.GetComponent<MeshRenderer>();
      gObjRender.reflectionProbeUsage = UnityEngine.Rendering.ReflectionProbeUsage.Off;
      gObjRender.sharedMaterial.SetTexture("_ReflProbeArray", reflProbeTexArray);
      gObjRender.sharedMaterial.SetTexture("_ProbeParams", reflProbeSettingsArray);
    }
    EditorUtility.ClearProgressBar();
  }

  private void FindAllStaticMeshes(GameObject currentObj, ref List<GameObject> staticObj)
  {

    if (GameObjectUtility.AreStaticEditorFlagsSet(currentObj, StaticEditorFlags.BatchingStatic))
    {
      MeshFilter meshFilter = currentObj.GetComponent<MeshFilter>();
      if (meshFilter != null)
      {
        staticObj.Add(currentObj);
      }
    }
    
    for (int child = 0; child < currentObj.transform.childCount; child++)
    {
      FindAllStaticMeshes(currentObj.transform.GetChild(child).gameObject, ref staticObj);
    }
   
  }

  private Mesh MakeMeshCopy(GameObject gObj, MeshProbes probeInfo)
  {
    Mesh currentMesh = gObj.GetComponent<MeshFilter>().sharedMesh;

    //
    string sceneFolder = Path.GetDirectoryName(SceneManager.GetActiveScene().path);
    string meshFolder = SceneManager.GetActiveScene().name + "_meshes";
    if (!AssetDatabase.IsValidFolder(sceneFolder + "\\" + meshFolder))
    {
      AssetDatabase.CreateFolder(sceneFolder, meshFolder);
    }
    string newMeshFilename = gObj.name + "_" + gObj.GetInstanceID().ToString() + ".asset";
    string newMeshPath = sceneFolder + "\\" + meshFolder + "\\" + newMeshFilename;
    Mesh newMesh = new Mesh();
    newMesh.Clear();
    EditorUtility.CopySerialized(currentMesh, newMesh);

    newMesh.name = gObj.name + "_" + gObj.GetInstanceID().ToString();
    float pack1 = Pack2ShortsInFloat((ushort)probeInfo.probeIndex[0], (ushort)probeInfo.probeIndex[1]);
    float pack2 = Pack2ShortsInFloat((ushort)probeInfo.probeIndex[2], (ushort)probeInfo.probeIndex[3]);

    /* Reflection probe weights used to be packed in the third uv, but then I discovered the bounds of a box projection really need to be expanded
     * to fit the mesh bounds so you don't get ugly seams in the middle of the mesh where one box ends. Either I would need to reorganize the probe
     * data texture so a unique texture is stored per mesh containing expanded bounds for each of its four probes, or I could calculate the probe
     * weights in the shader and pass the mesh bounds information in the space freed up in the uvs. I chose the latter option as it gives me more
     * freedom to do better weighting on a per-pixel basis. I kept the old code here in case I ever decide to do it the other way.
     */
    //float pack3 = Pack2ShortsInFloat(Mathf.FloatToHalf(probeInfo.probeWeight[0]), Mathf.FloatToHalf(probeInfo.probeWeight[1]));
    //float pack4 = Pack2ShortsInFloat(Mathf.FloatToHalf(probeInfo.probeWeight[2]), Mathf.FloatToHalf(probeInfo.probeWeight[3]));

    Bounds meshBounds = gObj.GetComponent<MeshRenderer>().bounds;

    Vector4[] packedProbeIndex = new Vector4[1];
    packedProbeIndex[0] = new Vector4(pack1, pack2, meshBounds.min.x, meshBounds.min.y);
    Vector4[] packedProbeIndicies = new Vector4[currentMesh.vertices.Length];
    ArrayExtensions.Fill<Vector4>(packedProbeIndicies, packedProbeIndex); // MASSIVELY faster than iterating through each element of the array and setting the value.
    newMesh.SetUVs(2, packedProbeIndicies);

    Vector4[] packedProbeBound = new Vector4[1];
    packedProbeBound[0] = new Vector4(meshBounds.min.z, meshBounds.max.x, meshBounds.max.y, meshBounds.max.z);
    Vector4[] packedProbeBounds = new Vector4[currentMesh.vertices.Length];
    ArrayExtensions.Fill<Vector4>(packedProbeBounds, packedProbeBound);
    newMesh.SetUVs(3, packedProbeBounds);

    if (!File.Exists(Application.dataPath + "\\" + newMeshPath))
    {
      AssetDatabase.CreateAsset(newMesh, newMeshPath);
    }
    else
    {
      Mesh oldMesh = AssetDatabase.LoadAssetAtPath<Mesh>(newMeshPath);
      EditorUtility.CopySerialized(newMesh, oldMesh);
      newMesh = oldMesh;
    }
    AssetDatabase.SaveAssets();
    return newMesh;
  }

  private float PackIntInFloat(int num)
  {
    byte[] intBytes = BitConverter.GetBytes(num);
    return BitConverter.ToSingle(intBytes, 0);
  }
  private float Pack2ShortsInFloat(ushort num1, ushort num2)
  {
    byte[] intBytes1 = BitConverter.GetBytes(num1);
    byte[] intBytes2 = BitConverter.GetBytes(num2);
    byte[] concatBytes = new byte[32];
    intBytes1.CopyTo(concatBytes, 0);
    intBytes2.CopyTo(concatBytes, 2);
    return BitConverter.ToSingle(concatBytes, 0);
  }

  private MeshProbes FindClosestProbes(List<ReflectionProbe> reflProbeList, GameObject obj)
  {
    ProbeDistance[] probes = new ProbeDistance[reflProbeList.Count];
    MeshRenderer mesh = obj.GetComponent<MeshRenderer>();
    for (int i = 0; i < reflProbeList.Count; i++)
    {
      ProbeDistance probeI = new ProbeDistance();
      probeI.probeIndex = i;
      probeI.probeDistance = BoxDistance(reflProbeList[i].bounds, mesh.bounds);
      /* if the probe and mesh overlap, weight the probe by the volume of the overlap. The less probeDistance is, the higher priority the probe is, so use the negative of the overlap volume*/
      probeI.probeDistance = probeI.probeDistance <= 0.0f ? -BoxOverlap(reflProbeList[i].bounds, mesh.bounds) : probeI.probeDistance;
      probes[i] = probeI;
    }
    Array.Sort(probes, (x, y) => x.probeDistance.CompareTo(y.probeDistance));
    MeshProbes closestProbes = new MeshProbes();
    closestProbes.probeIndex = new int[MAXPROBES];
    closestProbes.probeWeight = new float[MAXPROBES];
  
    for (int i = 0; i < MAXPROBES; i++)
    {
      closestProbes.probeIndex[i] = probes[i].probeIndex;
      // probes[i].overlapVolume / probeVolumeSum; // Not storing probe weights anymore
    }

    /*
    Debug.Log(String.Format("{0}: Probe 0: {1},  Weight: {2}, Probe 1: {3},  Weight: {4}, Probe 2: {5},  Weight: {6}, Probe 3: {7},  Weight: {8}",
        obj.name, reflProbeList[closestProbes.probeIndex[0]].name, closestProbes.probeWeight[0],
        reflProbeList[closestProbes.probeIndex[1]].name, closestProbes.probeWeight[1],
        reflProbeList[closestProbes.probeIndex[2]].name, closestProbes.probeWeight[2],
        reflProbeList[closestProbes.probeIndex[3]].name, closestProbes.probeWeight[3]
        ));
    */

    return closestProbes;
  }

  private float BoxOverlap(Bounds box1, Bounds box2)
  {
    Vector3 overlap = Vector3.Min(box1.max, box1.max) - Vector3.Max(box1.min, box2.min);
    return overlap.x * overlap.y * overlap.z;
  }

  private float BoxDistance(Bounds box1, Bounds box2)
  {
    Vector3 u = Vector3.Max(Vector3.zero, box1.min - box2.max);
    Vector3 v = Vector3.Max(Vector3.zero, box2.min - box1.max);

    return Mathf.Sqrt(u.magnitude * u.magnitude + v.magnitude * v.magnitude);
  }

  #endregion

}




