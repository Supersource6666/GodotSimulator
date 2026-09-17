using System;
using System.Collections.Generic;
using General;
using SubwaySimulation.Utils;
using UnityEngine;
using UnityEngine.Assertions;
using UnityEngine.UI;
using XCharts;

public class AxisForceData : MonoBehaviour
{
    private const int VAL_COUNT = 4;
    [SerializeField] private Transform AxisForce; // 只作为一个父物体传入
    [SerializeField] private int cacheMax = 2000;
    [SerializeField] private int intervalCnt; // 间隔多少数据展示一个折线
    [SerializeField] private int vihicleIndex = 1;
    [SerializeField] private GameObject m_LineChartParent;

    private int initCount = 0;

    private LineChart m_LineChart;
    private int m_SeriesCount;
    private float m_TmpTimer;
    [NonSerialized] private List<Toggle> Toggles = new List<Toggle>();
    private int tmpCurCount;

    private void Start()
    {
        ShowMW();
        m_LineChart.xAxis0.splitNumber = 1;
        m_LineChart.xAxis0.axisName.show = true;
        m_LineChart.xAxis0.axisName.name = "Time(s)";//enzh时间
        m_LineChart.xAxis0.axisName.textStyle.offset = new Vector2(0, 14f);
        m_LineChart.xAxis0.axisName.location = AxisName.Location.Middle;
        foreach (var series in m_LineChart.series.list)
        {
            series.symbol.type = SerieSymbolType.Circle;
            series.lineStyle.width = 2f;
        }
    }

    private void FixedUpdate()
    {
        if (m_LineChartParent.activeInHierarchy && m_SeriesCount == 0)
        {
            m_LineChartParent.SetActive(false);
        }

        if (Globle.IsStart && tmpCurCount != Globle.CurCount)
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
            m_LineChart.legends[0].data = new List<string> {"轴一", "轴二", "轴三", "轴四"};
            tmpCurCount = 0;
            m_TmpTimer = 0;
        }
    }

    public void ShowMW()
    {
        if (m_LineChart & AxisForce & Toggles.Count == VAL_COUNT) return;
        m_LineChart = Utility.FindChildRecursively(transform, "LineChartBody").GetComponent<LineChart>();
        // m_LineChart.ClearData();
        m_LineChart.SetMaxCache(cacheMax);
        // WheelRate = GameObject.Find("WheelRate").transform;
        for (int i = 1; i <= VAL_COUNT; i++)
        {
            Transform tmp;
            tmp = Utility.FindChildRecursively(AxisForce, $"Tog{i}");
            Toggles.Add(tmp.GetComponent<Toggle>());
        }

        for (var i = 0; i < VAL_COUNT; i++)
        {
            m_LineChart.series.GetSerie(i).show = false;
        }
    }
    
    public void ResetMW()
    {
        if (Toggles.Count == VAL_COUNT & m_SeriesCount == 0) return;
        for (var i = 0; i < VAL_COUNT; i++)
        {
            Toggles[i].isOn = false;
        }

        m_SeriesCount = 0;
    }

    void AddOneData()
    {
        float xvalue = Globle.Normal[vihicleIndex - 1][Globle.CurCount].time;
        if (xvalue >= m_TmpTimer)
            m_TmpTimer = xvalue;
        else return;

        // 控制x轴splitNumber
        AdjustXSplitNumber(xvalue);

        float[] yvalue = new float[VAL_COUNT];
        for (var i = 0; i < VAL_COUNT; i++)
        {
            yvalue[i] = Globle.Fwr[vihicleIndex - 1][Globle.CurCount].axisHForce[i];

            m_LineChart.yAxis0.max = m_LineChart.series.list[i].max > 0
                ? m_LineChart.series.list[i].max * 1.3f
                : m_LineChart.series.list[i].max * 0.7f;
            m_LineChart.yAxis0.min = m_LineChart.series.list[i].min < 0
                ? m_LineChart.series.list[i].min * 1.3f
                : m_LineChart.series.list[i].min * 0.7f;

            m_LineChart.AddData(i, xvalue, yvalue[i]);
        }

        // m_LineChart.AddXAxisData(xvalue.ToString("F5"));
    }

    // 传入一个index，根据对应index的toggle的is on来执行series是否可视
    public void SwitchSeries(int index)
    {
        if (Toggles[index].isOn)
        {
            if (!m_LineChartParent.activeInHierarchy)
            {
                m_LineChartParent.SetActive(true);
            }

            m_LineChart.series.GetSerie(index).show = true;

            if (Globle.isSimpackMode)
            {
                Assert.IsTrue(index + 4 < m_LineChart.series.Count);
                m_LineChart.series.GetSerie(index + 4).show = true;
            }

            m_SeriesCount++;
        }
        else
        {
            m_LineChart.series.GetSerie(index).show = false;

            if (Globle.isSimpackMode)
            {
                Assert.IsTrue(index + 4 < m_LineChart.series.Count);
                m_LineChart.series.GetSerie(index + 4).show = false;
            }
            
            m_SeriesCount--;
        }
    }

    private void AdjustXSplitNumber(float xValue)
    {
        m_LineChart.xAxis0.splitNumber = (int) (xValue + 1f);
    }
}