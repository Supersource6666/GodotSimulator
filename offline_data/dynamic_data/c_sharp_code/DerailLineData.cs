using System.Collections.Generic;
using General;
using SubwaySimulation.Utils;
using TMPro;
using UnityEngine;
using UnityEngine.UI;
using XCharts;

public class DerailLineData : MonoBehaviour
{
    private const int VAL_COUNT = 8;

    public TMP_FontAsset targetFont;
    public Transform Derailment; // 只作为一个父物体传入
    public int cacheMax = 2000;
    public int intervalCnt; // 间隔多少数据展示一个折线
    public int vihicleIndex = 1;
    public GameObject m_LineChartParent;
    private int initCount = 0;
    private LineChart m_LineChart;
    private int m_SeriesCount = 0;
    private float m_TmpTimer;
    private List<Toggle> m_Toggles = new List<Toggle>();
    private int tmpCurCount = 0;

    private void Start()
    {
        ShowMW();
        m_LineChart.xAxis0.splitNumber = 1;
        m_LineChart.xAxis0.axisName.show = true;
        m_LineChart.xAxis0.axisName.name = "时间(s)";
        m_LineChart.xAxis0.axisName.textStyle.offset = new Vector2(0, 14f);
        m_LineChart.xAxis0.axisName.location = AxisName.Location.Middle;
        foreach (var series in m_LineChart.series.list)
        {
            series.symbol.type = SerieSymbolType.Circle;
            series.lineStyle.width = 2f;
        }
        m_LineChart.theme.title.tmpFont = targetFont;
        m_LineChart.theme.subTitle.tmpFont = targetFont;
        m_LineChart.theme.tmpFont = targetFont;
    }

    private void FixedUpdate()
    {
        if (m_LineChartParent.activeInHierarchy && m_SeriesCount == 0)
        {
            m_LineChartParent.SetActive(false);
        }

        if (Globle.IsStart && tmpCurCount != Globle.CurCount && !Globle.isSimpackMode)
        {
            initCount++;
            if (initCount == intervalCnt)
            {
                AddOneData();
                initCount = 0;
            }

            tmpCurCount = Globle.CurCount;
        }

        // 如果isstart = false，刷新图表
        if (!Globle.IsStart & m_LineChart.series.GetSerie(0).dataCount != 0)
        {
            m_LineChart.ClearData();
            tmpCurCount = 0;
            m_TmpTimer = 0;
        }
    }

    public void ShowMW()
    {
        if (m_LineChart & Derailment & m_Toggles.Count == VAL_COUNT) return;
        m_LineChart = Utility.FindChildRecursively(transform, "LineChartBody").GetComponent<LineChart>();
        m_LineChart.ClearData();
        m_LineChart.SetMaxCache(cacheMax);
        // Derailment = GameObject.Find("Derailment").transform;
        for (int i = 1; i <= VAL_COUNT; i++)
        {
            Transform tmp;
            if (i < 5)
            {
                tmp = Utility.FindChildRecursively(Derailment, $"TogL{i}");
                m_Toggles.Add(tmp.GetComponent<Toggle>());
            }
            else
            {
                tmp = Utility.FindChildRecursively(Derailment, $"TogR{i - 4}");
                m_Toggles.Add(tmp.GetComponent<Toggle>());
            }
        }

        for (var i = 0; i < VAL_COUNT; i++)
        {
            m_LineChart.series.GetSerie(i).show = false;
        }
    }
    
    public void ResetMW()
    {
        if (m_Toggles.Count == VAL_COUNT & m_SeriesCount == 0) return;
        for (var i = 0; i < VAL_COUNT; i++)
        {
            m_Toggles[i].isOn = false;
        }

        m_SeriesCount = 0;
    }

    void AddOneData()
    {
        float xvalue = Globle.Normal[vihicleIndex - 1][Globle.CurCount].time;
        if (xvalue >= m_TmpTimer)
            m_TmpTimer = xvalue;
        else return;
        float[] yvalue = new float[VAL_COUNT];
        
        // 控制x轴splitNumber
        AdjustXSplitNumber(xvalue);
        
        for (var i = 0; i < VAL_COUNT; i++)
        {
            yvalue[i] = Globle.Fwr[vihicleIndex - 1][Globle.CurCount].drail[i];

            m_LineChart.yAxis0.max = m_LineChart.series.list[i].max>0?
                m_LineChart.series.list[i].max*1.3f:
                m_LineChart.series.list[i].max*0.7f;
            m_LineChart.yAxis0.min = m_LineChart.series.list[i].min<0?
                m_LineChart.series.list[i].min*1.3f:
                m_LineChart.series.list[i].min*0.7f;
            
            m_LineChart.AddData(i, xvalue, yvalue[i]);
        }
        // m_LineChart.AddXAxisData(xvalue.ToString("F5"));
    }

    // 传入一个index，根据对应index的toggle的is on来执行series是否可视
    public void SwitchSeries(int index)
    {
        if (m_Toggles[index].isOn)
        {
            if (!m_LineChartParent.activeInHierarchy)
            {
                m_LineChartParent.SetActive(true);
            }

            m_LineChart.series.GetSerie(index).show = true;
            m_SeriesCount++;
        }
        else
        {
            m_LineChart.series.GetSerie(index).show = false;
            m_SeriesCount--;
        }
    }
    
    private void AdjustXSplitNumber(float xValue)
    {
        m_LineChart.xAxis0.splitNumber = (int) (xValue + 1f);
    }
}