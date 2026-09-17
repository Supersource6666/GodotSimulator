using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Net;
using System.Text;
using System.Threading;
using DataStruct;
using General;
using Newtonsoft.Json;
using TMPro;
using UnityEngine;
using UnityEngine.Networking;
using Debug = UnityEngine.Debug;
using Utility = SubwaySimulation.Utils.Utility;

// 从文档中获取轮轨力 横向位移等数据
public class GetData : MonoBehaviour
{
    private const int FWR_WIDTH = 34; // 实际列数: time, velocity, 32 force values
    private const int WX_WIDTH = 18;  // 实际列数: time, velocity, 4 lateral, 4 vertical, 4 yaw, 4 pitch
    private const int VEHICLE_WIDTH = 58; // 6 12 
    private const int DATA_SLICE_NUM = 200;
    private const int DATA_START_NUM = 10;
    private const float MAX_VELOCITY = 380f; // 最大速度 km/h

    // public static List<List<Wx>> wx = new List<List<Wx>>(Globle.numVihicle);
    // public static List<List<Fwr>> fwr = new List<List<Fwr>>(Globle.numVihicle);
    // public static List<List<Vihicle>> vihicle = new List<List<Vihicle>>(Globle.numVihicle);
    // public static List<Cross> Cross = new List<Cross>();

    private static string[] loadString = new string[4];
    
    
    public TMP_InputField input;
    public int count = 0; // url中添加的要读第几部分的数据
    public string oriUrl;
    public GameObject UIHandler;
    public int readMode; // 0: 分片传输， 1: 本地读取， 2: 流传输

    public string[] dynamicFilePath;
    public string[] trackFilePath;
    private bool m_AllRead = false;
    private string m_Authorization;
    private bool m_CanGetCrossData = true;

    private bool m_CanGetDynamicData = true;
    private string m_LastLineDataFwr = ""; // 上组数据的最后一行
    private string m_LastLineDataVihicle = ""; // 上组数据的最后一行

    private string m_LastLineDataWx = ""; // 上组数据的最后一行
    private string[] m_LocalString; // index:0——三向轮轨力 1——车体加速度 2——轮对横移量 3——脱轨系数
    private int m_OkCount = 0; // 读了多少片数据
    private string m_Path;
    private string m_Res = "";
    private int m_StandardCount = 0; // 共读了多少数据
    private bool m_WebDone = false;
    private bool m_ShouldStop = false;
    private int m_FileIndex = 1;

    void Awake()
    {
        Init();
        waitForSecond();
    }

    IEnumerator waitForSecond()
    {
        yield return new WaitForSeconds(1.0f);
    }


    public void ParseCrossData()
    {
        print("parsecrossdata()");
        Debug.Log($"[ParseCrossData] loadString[0] 前200字符: {(loadString[0]?.Length > 200 ? loadString[0].Substring(0, 200) : loadString[0])}");
        ParseTrackJson(loadString[0]);
    }

    // 从 JSON 文本解析轨道数据（网络和本地共用）
    private void ParseTrackJson(string json)
    {
        try
        {
            if (string.IsNullOrEmpty(json))
            {
                Debug.LogError("ParseTrackJson: json is empty");
                return;
            }

            // 新 API 返回格式: {"horizontalTracks":[...],"verticalTracks":[...],...}
            // 提取 horizontalTracks 数组
            var jsonObj = Newtonsoft.Json.Linq.JObject.Parse(json);
            var tracksArray = jsonObj["horizontalTracks"]?.ToString();
            if (string.IsNullOrEmpty(tracksArray))
            {
                Debug.LogError("ParseTrackJson: horizontalTracks not found in response");
                return;
            }
            Globle.Cross = JsonConvert.DeserializeObject<List<TempCross>>(tracksArray);
            Debug.Log($"[ParseTrackJson] 解析成功, Cross.Count={Globle.Cross.Count}");
            for (int i = 0; i < Globle.Cross.Count; i++)
            {
                // 如果为直线，那么直线长度要用下一个里程减去该里程
                if (Globle.Cross[i].Radius[0] == '0' && Globle.Cross[i].Length == "0")
                {
                    if (i == Globle.Cross.Count) break;
                    Globle.Cross[i].Length = (Utility.StrToFloat(
                                                  Globle.Cross[i + 1].Millage) -
                                              Utility.StrToFloat(Globle.Cross[i]
                                                  .Millage))
                        .ToString();
                }

                Globle.TrackLength.Add(Utility.StrToFloat(Globle.Cross[i].Length));
            }

            Globle.SumTrackLength.Add(0);
            for (int i = 0; i < Globle.TrackLength.Count; i++)
            {
                Globle.SumTrackLength.Add(Globle.TrackLength[i] + Globle.SumTrackLength.Last());
            }

            Globle.TrackReadOK = true;
        }
        catch (Exception e)
        {
            Debug.Log(e.Message);
        }
    }

    // 解析数据，分片版本
    public void ParseWxData1(int vihicleIndex)
    {
        print("parseWxData1()");
        try
        {
            string[] ContentLines = loadString[1].Split(new string[] {"\r\n"}, StringSplitOptions.RemoveEmptyEntries);
            ContentLines = ContentLines.Skip(2).ToArray();
            string line;
            int idx = 0;
            while (idx < ContentLines.Length)
            {
                if (idx == 0 && m_LastLineDataWx.Length != 0)
                {
                    line = $"{m_LastLineDataWx}{ContentLines[idx++]}";
                }
                else
                {
                    line = ContentLines[idx++];
                }

                string[] arr = new string[WX_WIDTH];
                arr = line.Split(new []{' '}, StringSplitOptions.RemoveEmptyEntries);
                if (idx == ContentLines.Length)
                {
                    m_LastLineDataWx = line;
                    return;
                }

                Wx temp = new Wx();
                {
                    temp.time = Utility.StrToFloat(arr[0]);              // col 0: time(s)
                    temp.velocity = Mathf.Min(Utility.StrToFloat(arr[1]) * 3.6f, MAX_VELOCITY);   // col 1: m/s → km/h, 上限 380
                    temp.dis = temp.time * temp.velocity / 3.6f;          // dis(km)
                    temp.wheelDis = new List<float>();
                    for (var i = 0; i < 4; i++)
                    {
                        temp.wheelDis.Add(Utility.StrToFloat(arr[i + 2])); // col 2-5: wheel lateral(mm)
                    }
                }

                Normal tempNormal = new Normal();
                {
                    tempNormal.dis = temp.dis;
                    tempNormal.velocity = temp.velocity;
                    tempNormal.time = temp.time;
                }

                Globle.Normal[vihicleIndex - 1].Add(tempNormal);
                Globle.Wx[vihicleIndex - 1].Add(temp);
            }
        }
        catch (Exception e)
        {
            // 向用户显示出错消息
            Debug.Log(e.Message);
            Debug.Log(e.StackTrace);
        }
    }

    public void ParseFwrData1(int vihicleIndex)
    {
        print("parseFwrData1()");
        try
        {
            string[] ContentLines = loadString[2].Split(new string[] {"\r\n"}, StringSplitOptions.RemoveEmptyEntries);
            ContentLines = ContentLines.Skip(2).ToArray();
            string line;
            int idx = 0;
            while (idx < ContentLines.Length) // 最后一行单独读取
            {
                if (idx == 0 && m_LastLineDataFwr.Length != 0)
                {
                    line = $"{m_LastLineDataFwr}{ContentLines[idx++]}";
                }
                else
                {
                    line = ContentLines[idx++];
                }

                Fwr fwr = new Fwr();
                string[] arr = new string[FWR_WIDTH];
                arr = line.Split(new []{' '}, StringSplitOptions.RemoveEmptyEntries);
                if (arr.Length != FWR_WIDTH + 1 && idx == ContentLines.Length)
                {
                    m_LastLineDataFwr = line;
                    return;
                }

                // ---------old----------
                // fwr.time = Utility.StrToFloat(arr[1]);
                // fwr.dis = Utility.StrToFloat(arr[0]);
                fwr.vf = new float[8];
                fwr.hf = new float[8];
                fwr.lf = new float[8];
                fwr.drail = new float[8];
                fwr.reduction = new float[4];
                fwr.axisHForce = new float[4];
                // ---------old----------

                float vel_ms = Utility.StrToFloat(arr[1]);
                fwr.time = Utility.StrToFloat(arr[0]);              // col 0: time(s)
                fwr.dis = fwr.time * vel_ms * 3.6f / 3.6f;         // 保持和 WX 一致的单位换算

                int num = 0;
                for (int i = 2; i < FWR_WIDTH; i = i + 8)
                {
                    fwr.lf[num] = Utility.StrToFloat(arr[i]);
                    fwr.lf[num + 1] = Utility.StrToFloat(arr[i + 1]);
                    fwr.hf[num] = Utility.StrToFloat(arr[i + 2]);
                    fwr.hf[num + 1] = Utility.StrToFloat(arr[i + 3]);
                    fwr.vf[num] = Utility.StrToFloat(arr[i + 4]);
                    fwr.vf[num + 1] = Utility.StrToFloat(arr[i + 5]);
                    fwr.drail[num] = fwr.hf[num] / fwr.vf[num];
                    fwr.drail[num + 1] = fwr.hf[num + 1] / fwr.vf[num + 1];
                    fwr.reduction[num / 2] = (fwr.vf[num] - fwr.vf[num + 1]) / (fwr.vf[num] + fwr.vf[num + 1]);
                    fwr.axisHForce[num / 2] = fwr.hf[num] + fwr.hf[num + 1];
                    num += 2;
                }

                // ---------old----------
                // for (int i = 2; i < 10; i++)
                // {
                //     fwr.vf[i - 2] = Utility.StrToFloat(arr[i]);
                // }
                //
                // for (int i = 10; i < 14; i++)
                // {
                //     fwr.lf[i - 10] = Utility.StrToFloat(arr[i]);
                // }
                //
                // for (int i = 0; i < 4; i++)
                // {
                //     fwr.lf[i + 4] = 0f;
                // }
                //
                // for (int i = 14; i < 22; i++)
                // {
                //     fwr.hf[i - 14] = Utility.StrToFloat(arr[i]);
                // }
                //
                // for (int i = 22; i < 30; i++)
                // {
                //     fwr.drail[i - 22] = Utility.StrToFloat(arr[i]);
                // }
                //
                // for (int i = 30; i < 34; i++)
                // {
                //     fwr.reduction[i - 30] = Utility.StrToFloat(arr[i]);
                // }
                // ---------old----------

                Globle.Fwr[vihicleIndex - 1].Add(fwr);
            }
        }
        catch (Exception e)
        {
            // 向用户显示出错消息
            Debug.Log(e.Message);
        }
    }

    public void ParseVihicleData1(int vihicleIndex)
    {
        try
        {
            string[] ContentLines = loadString[3].Split(new string[] {"\r\n"}, StringSplitOptions.RemoveEmptyEntries);
            string line;
            int idx = 0;
            while (idx < ContentLines.Length)
            {
                if (idx == 0 && m_LastLineDataVihicle.Length != 0)
                {
                    line = $"{m_LastLineDataVihicle}{ContentLines[idx++]}";
                }
                else
                {
                    line = ContentLines[idx++];
                }

                string[] arr = new string[VEHICLE_WIDTH];
                arr = line.Split(new []{' '}, StringSplitOptions.RemoveEmptyEntries);
                if (arr.Length != VEHICLE_WIDTH + 1 && idx == ContentLines.Length)
                {
                    m_LastLineDataVihicle = line;
                    return;
                }

                Vehicle temp = new Vehicle();
                {
                    temp.dis = Utility.StrToFloat(arr[0]);
                    temp.time = Utility.StrToFloat(arr[1]);
                    temp.speed = Utility.StrToFloat(arr[2]);
                    temp.la = Utility.StrToFloat(arr[3]);
                    temp.ha = Utility.StrToFloat(arr[4]);
                    temp.va = Utility.StrToFloat(arr[5]);
                    Globle.Vehicle[vihicleIndex - 1].Add(temp);
                }
            }
        }
        catch (Exception e)
        {
            // 向用户显示出错消息
            Debug.Log(e.Message);
        }
    }

    // mode = 1: 轨道参数 mode = 2: 动力学参数
    void LoadFile(int mode)
    {
        print("LoadFile()");

        if (mode == 1)
        {
            ParseCrossData();
            Globle.TrackReadOK = true;
        }

        if (mode == 2)
        {
            // 多节车数据
            // for (int index = 1; index <= Globle.numVihicle; index++)
            // {
            //     ReadWxData(index);
            //     ReadFwrData(index);
            //     ReadVihicleData(index);
            // }

            ParseWxData1(1);
            ParseFwrData1(1);
            // ReadVihicleData(1);

            Debug.Log($"[LoadFile] Wx[0].Count={Globle.Wx[0].Count}, Fwr[0].Count={Globle.Fwr[0].Count}, Normal[0].Count={Globle.Normal[0].Count}");
            Globle.CountData = Math.Min(Globle.Wx[0].Count, Globle.Fwr[0].Count);
            Debug.Log($"[LoadFile] CountData={Globle.CountData}");

            if (m_OkCount >= DATA_START_NUM)
            {
                Globle.ReadOK = true;
            }

            Debug.Log($"dynamic read ok");
            m_OkCount++;
            if (m_OkCount == DATA_SLICE_NUM)
            {
                Globle.AllRead = true;
            }
        }
    }

    IEnumerator wait(float time)
    {
        yield return new WaitForSeconds(time);
    }

    public void RequireData(string url)
    {
        int pos = url.IndexOf("result");
        if (Globle.ReadMode == 0)
        {
            if (pos != -1 & m_CanGetDynamicData)
            {
                m_CanGetDynamicData = false;
                Debug.Log("getdynamicdata");
                UIHandler.SendMessage("SetRequire");
                StartCoroutine("GetDynamicRequest", url);
            }
        }
        else if (Globle.ReadMode == 2)
        {
            if (pos != -1 & m_CanGetDynamicData)
            {
                m_CanGetDynamicData = false;
                Debug.Log("getdynamicdata");
                UIHandler.SendMessage("SetRequire");
                url += "?count=6&total=20"; // todo: 这里count和total是不需要的,只是当前后端需要
                StartCoroutine("ReadFileStream", url);
            }
        }
        else if (Globle.ReadMode == 4)
        {
            // 实时文件流
            if (pos != -1 & m_CanGetDynamicData)
            {
                m_CanGetDynamicData = false;
                Debug.Log("getdynamicdata");
                UIHandler.SendMessage("SetRequire");
                ThreadPool.QueueUserWorkItem(ReadFileStreamInTime);
            }
        }

        if (pos == -1 & m_CanGetCrossData)
        {
            m_CanGetCrossData = false;
            Debug.Log("getcrossdata");
            StartCoroutine("GetCrossRequest", url);
        }
    }

    private void GetLocalData()
    {
        print("GetLocalData()");
        if (dynamicFilePath.Length != 0)
        {
            Debug.Log($"选用的本地动力学数据文件: {string.Join(", ", dynamicFilePath)}");
            GetLocalDynamicData(dynamicFilePath);
        }
        if (trackFilePath.Length != 0)
        {
            Debug.Log($"选用的本地轨道数据文件: {string.Join(", ", trackFilePath)}");
            GetLocalTrackData(trackFilePath);
        }
    }

    private void GetLocalDynamicData(string[] path)
    {
        print("GetLocalDynamicData()");

        // 共有 四个文件，分别为轮轨力、车体加速度、轮对横移量、脱轨系数
        var timer = Time.realtimeSinceStartupAsDouble;
        if (path[0].Length > 0)
        {
            using (FileStream fs = new FileStream(path[0], FileMode.Open, FileAccess.Read))
            {
                using (StreamReader sr = new StreamReader(fs, Encoding.UTF8))
                {
                    //记录每次读取的一行记录
                    string strLine = "";
                    //记录每行记录中的各字段内容
                    string[] aryLine = null;
                    int count = 0;
                    // 空行
                    int emptyCount = 0;
                    //逐行读取CSV中的数据
                    while ((strLine = sr.ReadLine()) != null)
                    {
                        // 跳过空行
                        if (emptyCount < 4)
                        {
                            emptyCount++;
                            continue;
                        }

                        Fwr fwr = new Fwr();
                        // todo: 2.27项目
                        // {
                        //     aryLine = strLine.Split(',');
                        //     fwr.time = Utility.StrToFloat(aryLine[1]);
                        fwr.vf = new float[8];
                        fwr.hf = new float[8];
                        fwr.lf = new float[8];
                        fwr.drail = new float[8];
                        fwr.reduction = new float[4];
                        fwr.axisHForce = new float[4];
                        //     fwr.time = Utility.StrToFloat(aryLine[1]);
                        //     fwr.dis = fwr.time * 80 / 3.6f;
                        // }

                        aryLine = strLine.Split(new []{' '}, StringSplitOptions.RemoveEmptyEntries);
                        fwr.time = Utility.StrToFloat(aryLine[0]);
                        fwr.dis = fwr.time * Utility.StrToFloat(aryLine[1]) * 3.6f / 3.6f;
                        int num = 0;
                        for (int i = 2; i < FWR_WIDTH; i = i + 8)
                        {
                            fwr.lf[num] = Utility.StrToFloat(aryLine[i]);
                            fwr.lf[num + 1] = Utility.StrToFloat(aryLine[i + 1]);
                            fwr.hf[num] = Utility.StrToFloat(aryLine[i + 2]);
                            fwr.hf[num + 1] = Utility.StrToFloat(aryLine[i + 3]);
                            fwr.vf[num] = Utility.StrToFloat(aryLine[i + 4]);
                            fwr.vf[num + 1] = Utility.StrToFloat(aryLine[i + 5]);
                            fwr.drail[num] = fwr.hf[num] / fwr.vf[num];
                            fwr.drail[num + 1] = fwr.hf[num + 1] / fwr.vf[num + 1];
                            fwr.reduction[num / 2] = (fwr.vf[num] - fwr.vf[num + 1]) / (fwr.vf[num] + fwr.vf[num + 1]);
                            fwr.axisHForce[num / 2] = fwr.hf[num] + fwr.hf[num + 1];
                            num += 2;
                        }

                        // todo: 2.27项目
                        // for (var l = 0; l < 8; l++)
                        // {
                        //     int index = l * 3 + 2;
                        //     fwr.lf[l] = Utility.StrToFloat(aryLine[index]);
                        //     fwr.hf[l] = Utility.StrToFloat(aryLine[index + 1]);
                        //     fwr.vf[l] = Utility.StrToFloat(aryLine[index + 2]);
                        // }

                        Globle.Fwr[0].Add(fwr);
                    }

                    sr.Close();
                    fs.Close();
                }
            }
        }

        if (path[3].Length > 0)
        {
            using (FileStream fs = new FileStream(path[3], FileMode.Open, FileAccess.Read))
            {
                using (StreamReader sr = new StreamReader(fs, Encoding.UTF8))
                {
                    //记录每次读取的一行记录
                    string strLine = "";
                    //记录每行记录中的各字段内容
                    string[] aryLine = null;
                    int count = 0;
                    //逐行读取CSV中的数据
                    while ((strLine = sr.ReadLine()) != null)
                    {
                        aryLine = strLine.Split(',');
                        Globle.Fwr[0][count].drail = new float[8];
                        for (var l = 1; l < 9; l++)
                        {
                            Globle.Fwr[0][count].drail[l - 1] = Utility.StrToFloat(aryLine[l]);
                        }

                        count++;
                    }

                    sr.Close();
                    fs.Close();
                }
            }
        }

        if (path[1].Length > 0)
        {
            using (FileStream fs = new FileStream(path[1], FileMode.Open, FileAccess.Read))
            {
                using (StreamReader sr = new StreamReader(fs, Encoding.UTF8))
                {
                    //记录每次读取的一行记录
                    string strLine = "";
                    //记录每行记录中的各字段内容
                    string[] aryLine = null;
                    //逐行读取CSV中的数据
                    while ((strLine = sr.ReadLine()) != null)
                    {
                        aryLine = strLine.Split(',');
                        Vehicle tmp = new Vehicle();
                        tmp.la = Utility.StrToFloat(aryLine[0]);
                        tmp.ha = Utility.StrToFloat(aryLine[1]);
                        tmp.va = Utility.StrToFloat(aryLine[2]);
                        Globle.Vehicle[0].Add(tmp);
                    }

                    sr.Close();
                    fs.Close();
                }
            }
        }

        if (path[0].Length > 0)
        {
            using (FileStream fs = new FileStream(path[2], FileMode.Open, FileAccess.Read))
            {
                using (StreamReader sr = new StreamReader(fs, Encoding.UTF8))
                {
                    //记录每次读取的一行记录
                    string strLine = "";
                    //记录每行记录中的各字段内容
                    string[] aryLine = null;
                    int emptyCount = 0;
                    //逐行读取CSV中的数据
                    while ((strLine = sr.ReadLine()) != null)
                    {
                        // 跳过空行
                        if (emptyCount < 4)
                        {
                            emptyCount++;
                            continue;
                        }

                        // aryLine = strLine.Split(',');
                        aryLine = strLine.Split(' ');
                        Wx temp = new Wx();
                        // temp.z1Dis = Utility.StrToFloat(aryLine[1]);
                        // temp.z2Dis = Utility.StrToFloat(aryLine[2]);
                        // temp.z3Dis = Utility.StrToFloat(aryLine[3]);
                        // temp.z4Dis = Utility.StrToFloat(aryLine[4]);


                        aryLine = strLine.Split(new[]{' '}, StringSplitOptions.RemoveEmptyEntries);
                        temp.time = Utility.StrToFloat(aryLine[0]);
                        temp.velocity = Mathf.Min(Utility.StrToFloat(aryLine[1]) * 3.6f, MAX_VELOCITY);
                        temp.dis = temp.time * temp.velocity / 3.6f;
                        temp.wheelDis = new List<float>();
                        for (var i = 0; i < 4; i++)
                        {
                            temp.wheelDis.Add(Utility.StrToFloat(aryLine[i + 2]));
                        }

                        Normal tempNormal = new Normal
                        {
                            dis = temp.dis,
                            velocity = temp.velocity,
                            time = temp.time
                        };
                        Globle.Normal[0].Add(tempNormal);
                        Globle.Wx[0].Add(temp);
                    }

                    sr.Close();
                    fs.Close();
                }
            }
        }


        timer = Time.realtimeSinceStartupAsDouble - timer;
        Debug.Log($"读取数据用时:{timer}");
        Globle.CountData = Globle.Wx[0].Count;
        Globle.ReadOK = true;
    }

    private void GetLocalTrackData(string[] path)
    {
        print("GetLocalTrackData()");
        try
        {
            // path[0] 是轨道数据 JSON 文件的本地路径
            string trackFile = path.Length > 0 ? path[0] : "";
            if (string.IsNullOrEmpty(trackFile))
            {
                Debug.LogWarning("GetLocalTrackData: track file path is empty");
                return;
            }

            // 如果是相对路径（不含盘符），自动拼 StreamingAssets 前缀
            if (!Path.IsPathRooted(trackFile))
            {
                trackFile = Path.Combine(Application.streamingAssetsPath, trackFile);
            }

            if (!File.Exists(trackFile))
            {
                Debug.LogError($"GetLocalTrackData: file not found: {trackFile}");
                return;
            }

            string json = File.ReadAllText(trackFile);
            Debug.Log($"[GetLocalTrackData] 读取本地轨道文件: {trackFile}, 大小={json.Length} 字符");
            ParseTrackJson(json);
        }
        catch (Exception e)
        {
            Debug.LogError($"GetLocalTrackData error: {e.Message}");
        }
    }

    public void SetAuthorization(string a)
    {
        m_Authorization = a;
    }

    // 分片传输 获取原始仿真数据
    IEnumerator GetDynamicRequest(string url)
    {
        Stopwatch sw = new Stopwatch();
        oriUrl = url;
        WWWForm wwwForm = new WWWForm();
        int cnt = 0;
        for (count = 1; count <= DATA_SLICE_NUM; count++)
        {
            sw.Start();
            url = oriUrl + $"?counts={count}&total={DATA_SLICE_NUM}";
            Debug.Log($"[GetDynamicRequest] 请求URL: {url}, Authorization: {m_Authorization}");
            // using (UnityWebRequest webRequest = UnityWebRequest.Post(url, wwwForm))
            using (UnityWebRequest webRequest = UnityWebRequest.Get(url))
            {
                webRequest.SetRequestHeader("Authorization", m_Authorization);
                // webRequest.SetRequestHeader("Content-Type", "application/json");
                // webRequest.SetRequestHeader("Accept", "application/json");
                yield return webRequest.SendWebRequest();
                if (!string.IsNullOrEmpty(webRequest.error))
                {
                    string nofi = "连接服务器失败";
                    // UIHandler.SendMessage("ShowNofication",nofi);
                    Debug.LogError($"{nofi} URL={url}, Error={webRequest.error}, Code={webRequest.responseCode}, Response={webRequest.downloadHandler.text}");
                    m_CanGetDynamicData = true;
                }
                else
                {
                    try
                    {
                        m_Res = webRequest.downloadHandler.text;
                        var wrapper = JsonConvert.DeserializeObject<TempResultWrapper>(m_Res);
                        if (wrapper == null || wrapper.value == null || wrapper.value.Count < 2)
                        {
                            Debug.LogError($"[GetDynamicRequest] 数据不足, value count={wrapper?.value?.Count}");
                            m_CanGetDynamicData = true;
                            continue;
                        }
                        // resultBytes 是 base64，解码为原始文件内容
                        loadString[1] = System.Text.Encoding.UTF8.GetString(System.Convert.FromBase64String(wrapper.value[1].resultBytes));
                        loadString[2] = System.Text.Encoding.UTF8.GetString(System.Convert.FromBase64String(wrapper.value[0].resultBytes));
                        Debug.Log($"[GetDynamicRequest] loadString[1] 前200字符: {(loadString[1]?.Length > 200 ? loadString[1].Substring(0, 200) : loadString[1])}");
                        Debug.Log($"[GetDynamicRequest] loadString[2] 前200字符: {(loadString[2]?.Length > 200 ? loadString[2].Substring(0, 200) : loadString[2])}");
                        // loadString[3] = System.Text.Encoding.UTF8.GetString(temp[2].resultBytes);
                    }
                    catch (Exception e)
                    {
                        Debug.Log(e);
                    }

                    LoadFile(2);
                    sw.Stop();
                    Debug.Log(sw.Elapsed.Milliseconds);
                }
            }
        }
    }

    // 获取轨道原始数据
    IEnumerator GetCrossRequest(string url)
    {
        oriUrl = url;
        WWWForm wwwForm = new WWWForm();
        url = oriUrl;
        Debug.Log($"[GetCrossRequest] 请求URL: {url}");
        Debug.Log($"[GetCrossRequest] Authorization: {m_Authorization}");
        using (UnityWebRequest webRequest = UnityWebRequest.Get(url))
        {
            webRequest.SetRequestHeader("Authorization", m_Authorization);
            webRequest.SetRequestHeader("Content-Type", "application/json");
            webRequest.SetRequestHeader("Accept", "application/json");
            yield return webRequest.SendWebRequest();
            if (!string.IsNullOrEmpty(webRequest.error))
            {
                string nofi = "获取轨道数据失败";
                Debug.LogError($"{nofi} URL={url}, Error={webRequest.error}, Code={webRequest.responseCode}, Response={webRequest.downloadHandler.text}");
                m_CanGetCrossData = true;
            }
            else
            {
                try
                {
                    List<TempCross> temp;
                    loadString[0] = "";
                    m_Res = webRequest.downloadHandler.text;
                    // temp = JsonConvert.DeserializeObject<List<TempCross>>(m_Res);
                    loadString[0] = m_Res;
                }
                catch (Exception e)
                {
                    Console.WriteLine(e);
                }

                LoadFile(1);
            }
        }
    }

    // 文件流传输 readMode = 2
    IEnumerator ReadFileStream(string url)
    {
        print("ReadFileStream()");
        var request = (HttpWebRequest) WebRequest
            .Create(url);
        request.Method = "GET";
        request.Timeout = 6000;
        var response = (HttpWebResponse) request.GetResponse();
        var streamReader = new StreamReader(response.GetResponseStream());
        using (var fileStream = new FileStream("D:/Work/unity/visualization-part-of-the-cloud-platform/data/1.dat",
            FileMode.Create, FileAccess.ReadWrite))
        {
            using (var writer = new StreamWriter(fileStream))
            {
                while (!streamReader.EndOfStream)
                {
                    var content = streamReader.ReadLine();
                    ParseFileStream(content, 1);
                    Globle.ReadOK = true;
                    Globle.CountData++;
                    yield return null;
                    if (content != null) writer.WriteLine(content.ToCharArray());
                }
            }
        }

        Globle.AllRead = true;
        streamReader.Close();
    }

    internal class Paths
    {
        public string Fwr;
        public string Wx;
        public string Vehicle;
        public string Motor;
    }

    internal class PathsDto
    {
        public Paths paths;
        public int code;
        public string message;
    }

    // 实时文件流传输 readMode = 4
    public void ReadFileStreamInTime(object o)
    {
        print("ReadFileStreamInTime()");
        Debug.Log("into ReadFileStreamInTime");
        var pathsDto = new PathsDto();
        var url = $"http://{Globle.BackendAddr}/api/cttsim/results/receive/{Globle.CurTask.ProjectID}";
        while (GetDataFile(url, m_FileIndex, ref pathsDto))
        {
            if (m_ShouldStop)
            {
                Debug.Log("主线程已结束.");
                break;
            }
            
            if (Globle.CurTask.NTotal!=0 && m_FileIndex > Globle.CurTask.NTotal)
            {
                Debug.Log($"getdatafile: {Globle.CurTask.NTotal}");
                Debug.Log("所有结果文件读完");
                break;
            }
            
            if (!checkPaths(pathsDto.paths))
            {
                // 保证后端四个数据都有
                Thread.Sleep(2000);
                Debug.Log($"false checkPaths");
                continue;
            }

            try
            {
                FileStream fsFwr = new FileStream(Globle.RootResultPath + pathsDto.paths.Fwr, FileMode.Open);
                byte[] data = new byte[fsFwr.Length];
                fsFwr.Read(data, 0, (int) fsFwr.Length);
                var content = Encoding.UTF8.GetString(data);
                ParseFwrData(content);
                fsFwr.Close();

                FileStream fsWx = new FileStream(Globle.RootResultPath + pathsDto.paths.Wx, FileMode.Open);
                data = new byte[fsWx.Length];
                fsWx.Read(data, 0, (int) fsWx.Length);
                content = Encoding.UTF8.GetString(data);
                ParseWxData(content);
                fsWx.Close();

                FileStream fsVehicle = new FileStream(Globle.RootResultPath + pathsDto.paths.Vehicle, FileMode.Open);
                data = new byte[fsVehicle.Length];
                fsVehicle.Read(data, 0, (int) fsVehicle.Length);
                content = Encoding.UTF8.GetString(data);
                ParseVehicleData(content);
                fsVehicle.Close();
            }
            catch (Exception e)
            {
                Debug.Log(e.StackTrace);
                throw;
            }

            m_FileIndex++;
            Globle.ReadOK = true;
            
            Thread.Sleep(500);
        }

        Debug.Log("all read");
        Globle.AllRead = true;
    }

    private void ParseVehicleData(string content)
    {
        print("ParseVehicleData()");
        string[] ContentLines = content.Split(new[] {"\r\n"}, StringSplitOptions.RemoveEmptyEntries);
        string line;
        int idx = 0;
        while (idx < ContentLines.Length)
        {
            line = ContentLines[idx];
            Vehicle vehicle = new Vehicle();
            Normal normal = new Normal();
            string[] arr = new string[VEHICLE_WIDTH];
            line = line.Replace("  ", " ");
            line = line.TrimEnd(' ');
            var tempArr = line.Split(' ');
            if (tempArr.Length < VEHICLE_WIDTH)
            {
                // 数据缺失，后面的数据也不用读了
                break;
            }
            arr = tempArr;

            normal.dis = Utility.StrToFloat(arr[0]);
            normal.time = Utility.StrToFloat(arr[1]);
            normal.velocity = Utility.StrToFloat(arr[2]);
            vehicle.la = Utility.StrToFloat(arr[3]);
            vehicle.ha = Utility.StrToFloat(arr[4]);
            vehicle.va = Utility.StrToFloat(arr[5]);
            vehicle.frameHa = new float[2];
            vehicle.frameLa = new float[2];
            vehicle.frameVa = new float[2];
            // 构架解析
            for (int i = 0; i < 2; i++)
            {
                int tmp = 6 + i * 3;
                vehicle.frameLa[i] = Utility.StrToFloat(arr[tmp]);
                vehicle.frameHa[i] = Utility.StrToFloat(arr[tmp+1]);
                vehicle.frameVa[i] = Utility.StrToFloat(arr[tmp+2]);
            }

            Globle.Vehicle[0].Add(vehicle);
            Globle.Normal[0].Add(normal);
            idx++;
        }

        Globle.CountData += idx;
    }

    private void ParseWxData(string content)
    {
        print("ParseWxData()");
        string[] ContentLines = content.Split(new[] {"\r\n"}, StringSplitOptions.RemoveEmptyEntries);
        string line;
        int idx = 0;
        while (idx < ContentLines.Length)
        {
            line = ContentLines[idx];
            Wx wx = new Wx();
            
            string[] arr = new string[WX_WIDTH];
            line = line.Replace("  ", " ");
            line = line.TrimEnd(' ');
            var tempArr = line.Split(' ');
            if (tempArr.Length < WX_WIDTH)
            {
                // 数据缺失，后面的数据也不用读了
                break;
            }
            arr = tempArr;

            wx.wheelDis = new List<float>();

            // 轮对横移
            for (int i = 0; i < 4; i++)
            {
                var index = i + 3;
                wx.wheelDis.Add(Utility.StrToFloat(arr[index]));
            }

            Globle.Wx[0].Add(wx);
            idx++;
        }
    }

    private void ParseFwrData(string content)
    {
        print("ParseFwrData()");
        string[] ContentLines = content.Split(new[] {"\r\n"}, StringSplitOptions.RemoveEmptyEntries);
        string line;
        int idx = 0;
        while (idx < ContentLines.Length)
        {
            line = ContentLines[idx];
            Fwr fwr = new Fwr();
            
            string[] arr = new string[FWR_WIDTH];
            line = line.Replace("  ", " ");
            line = line.TrimEnd(' ');
            var tempArr = line.Split(' ');
            if (tempArr.Length < FWR_WIDTH)
            {
                // 数据缺失，后面的数据也不用读了
                break;
            }
            arr = tempArr;

            fwr.vf = new float[8];
            fwr.hf = new float[8];
            fwr.lf = new float[8];
            fwr.drail = new float[8];
            fwr.reduction = new float[4];
            fwr.axisHForce = new float[4];

            int num = 0;

            // 垂向力
            for (int i = 0; i < 4; i++)
            {
                var index = i + 2;
                fwr.vf[2 * i] = Utility.StrToFloat(arr[index]);
                fwr.vf[2 * i + 1] = Utility.StrToFloat(arr[index + 4]);
            }

            // 纵向力
            for (int i = 0; i < 4; i++)
            {
                var index = i + 10;
                fwr.lf[2 * i] = Utility.StrToFloat(arr[index]);
                fwr.lf[2 * i + 1] = Utility.StrToFloat(arr[index]);
            }

            // 横向力
            for (int i = 0; i < 4; i++)
            {
                var index = i + 14;
                fwr.hf[2 * i] = Utility.StrToFloat(arr[index]);
                fwr.hf[2 * i + 1] = Utility.StrToFloat(arr[index + 4]);
            }

            // 轮轴横向力
            for (int i = 0; i < 4; i++)
            {
                var index = i + 22;
                fwr.axisHForce[i] = Utility.StrToFloat(arr[index]);
            }

            // 轮重减载率
            for (int i = 0; i < 4; i++)
            {
                var index = i + 26;
                fwr.drail[2 * i] = Utility.StrToFloat(arr[index]);
                fwr.drail[2 * i + 1] = Utility.StrToFloat(arr[index + 4]);
            }

            // 脱轨系数
            for (int i = 0; i < 4; i++)
            {
                var index = i + 34;
                fwr.reduction[i] = Utility.StrToFloat(arr[index]);
            }

            Globle.Fwr[0].Add(fwr);
            idx++;
        }
    }

    // 实时传输模式下 获取一个要读取的文件
    private bool GetDataFile(string url, int index, ref PathsDto paths)
    {
        print("GetDataFile()");
        // 临时调试
        // url = "http://119.167.81.178:44359/api/cttsim/results/receive/3a056e8f-9af6-c4d9-e017-c632d9c9e1c2";
        url += $"?index={index}";
        Debug.Log($"GetDataFile: {url}");
        try
        {
            var req = (HttpWebRequest) WebRequest.Create(url);
            req.Timeout = 6000;
            req.Method = "GET";
            
            var rsp = (HttpWebResponse)req.GetResponse();
            var stream = rsp.GetResponseStream();
            var reader = new StreamReader(stream, Encoding.UTF8);
            var data = reader.ReadToEnd();
            
            paths = JsonConvert.DeserializeObject<PathsDto>(data);
            // if (paths.code != 200)
            // {
            //     return true;
            // }

            return true;
        }
        catch (Exception e)
        {
            Debug.Log(e.Message);
            Console.WriteLine(e);
        }

        return false;
    }

    private bool checkPaths(Paths paths)
    {
        if (paths == null)
        {
            return false;
        }
        
        if (paths.Fwr == "" | paths.Motor == "" | paths.Vehicle == "" | paths.Wx == "")
        {
            return false;
        }

        return true;
    }

    private void ParseFileStream(string content, int vihicleIndex)
    {
        print("ParseFileStream()");
        string[] arr = new string[WX_WIDTH + FWR_WIDTH];
        arr = content.Split(' ');

        // 解析wx数据
        Wx temp = new Wx();
        {
            temp.time = Utility.StrToFloat(arr[1]);
            temp.velocity = Utility.StrToFloat(arr[2]);
            temp.dis = temp.time * temp.velocity / 3.6f;
            temp.wheelDis = new List<float>();
            for (var i = 0; i < 4; i++)
            {
                temp.wheelDis.Add(Utility.StrToFloat(arr[i + 3]));
            }
        }

        // 解析normal数据
        Normal tempNormal = new Normal();
        {
            tempNormal.dis = temp.dis;
            tempNormal.velocity = temp.velocity;
            tempNormal.time = temp.time;
        }

        // 解析fwr数据
        Fwr fwr = new Fwr();
        fwr.vf = new float[8];
        fwr.hf = new float[8];
        fwr.lf = new float[8];
        fwr.drail = new float[8];
        fwr.reduction = new float[4];
        fwr.axisHForce = new float[4];
        int num = 0;
        for (int i = 4 + WX_WIDTH; i < FWR_WIDTH + WX_WIDTH; i = i + 8)
        {
            fwr.lf[num] = Utility.StrToFloat(arr[i]);
            fwr.lf[num + 1] = Utility.StrToFloat(arr[i + 1]);
            fwr.hf[num] = Utility.StrToFloat(arr[i + 2]);
            fwr.hf[num + 1] = Utility.StrToFloat(arr[i + 3]);
            fwr.vf[num] = Utility.StrToFloat(arr[i + 4]);
            fwr.vf[num + 1] = Utility.StrToFloat(arr[i + 5]);
            fwr.drail[num] = fwr.hf[num] / fwr.vf[num];
            fwr.drail[num + 1] = fwr.hf[num + 1] / fwr.vf[num + 1];
            fwr.reduction[num / 2] = (fwr.vf[num] - fwr.vf[num + 1]) / (fwr.vf[num] + fwr.vf[num + 1]);
            fwr.axisHForce[num / 2] = fwr.hf[num] + fwr.hf[num + 1];
            num += 2;
        }


        Globle.Normal[vihicleIndex - 1].Add(tempNormal);
        Globle.Wx[vihicleIndex - 1].Add(temp);
        Globle.Fwr[vihicleIndex - 1].Add(fwr);
    }

    // // readMode = 2时，首先尝试从本地读取数据，如果无数据文件则通过Http获取文件流
    // private bool TryReadLocal()
    // {
    //     
    // }

    private void OnDestroy()
    {
        m_ShouldStop = true;
    }

    private void Init()
    {
        Globle.ReadMode = readMode;
        for (int i = 0; i < Globle.NumVihicle; i++)
        {
            List<Wx> tmpWx = new List<Wx>();
            List<Fwr> tmpFwr = new List<Fwr>();
            List<Vehicle> tmpVihicle = new List<Vehicle>();
            List<Normal> tmpNormal = new List<Normal>();
            Globle.Wx.Add(tmpWx);
            Globle.Fwr.Add(tmpFwr);
            Globle.Vehicle.Add(tmpVihicle);
            Globle.Normal.Add(tmpNormal);
        }

        if (Globle.ReadMode == 1)
        {
            GetLocalData();
            Globle.AllRead = true;
        }

        if (Globle.ReadMode == 2)
        {
        }
    }
}