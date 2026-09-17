using System.Collections.Generic;
using FluffyUnderware.DevTools.Extensions;
using General;
using TMPro;
using UnityEngine;
using UnityEngine.EventSystems;
using XCharts;

public class LineDataShow : MonoBehaviour
{
    public LineChart[] lc; // wheel axis1 line chart 轮1数据折线图
    public int cacheMax = 2000;
    public int intervalCnt; // 间隔多少数据展示一个折线
    public TMP_FontAsset mFont;
    public int vihicleIndex = 1;
    private int initCount = 0; // 用来计数
    private float m_TmpTimer;
    private int tmpCurCount = 0;

    // 三向数据的最大值最小值
    private List<float> m_triMax = new List<float>();
    private List<float> m_triMin = new List<float>();
    private float m_Max;
    private float m_Min;

    private void Awake()
    {
        lc.ForEach(i =>
        {
            i.ClearData();
            // i.xAxis0.interval = 1;
            i.xAxis0.splitNumber = 1;
            i.xAxis0.axisName.show = true;
            i.xAxis0.axisName.name = "Time(s)";//enzh"时间(s)";
            i.xAxis0.axisLabel.show = false;
            i.xAxis0.axisName.textStyle.offset = new Vector2(0, 14f);
            i.xAxis0.axisName.location = AxisName.Location.Middle;
            i.xAxis0.type = Axis.AxisType.Value;
            i.SetMaxCache(cacheMax);
            init(i.name);
            i.theme.title.tmpFont = mFont;
            i.theme.subTitle.tmpFont = mFont;
            i.theme.tmpFont = mFont;
            i.tooltip.numericFormatter = "N";
            i.legend.location = Location.defaultTop;
            i.legend.location.top = 46.5f;
            i.legend.textStyle.fontSize = 16;
            i.legend.textStyle.color = Color.white;
            i.title.location = Location.defaultTop;
            i.title.location.top = 1.5f;
            i.title.textStyle.fontSize = 18;
            i.title.subTextStyle.fontSize = 18;
            i.grid.top = 76.5f;
            foreach (var yAx in i.yAxes)
            {
                yAx.axisLabel.numericFormatter = "G2";
                yAx.minMaxType = Axis.AxisMinMaxType.MinMax;
            }

            foreach (var series in i.series.list)
            {
                // series.symbol.type = SerieSymbolType.Circle;
                series.lineStyle.width = 2f;
            }

            // 如果显示三向力、加速度，则取出一个y轴的label，以免重复
            if (i.yAxes.Count == 3)
            {
                for (var k = 1; k < i.series.Count; k++)
                {
                    var serie = i.series.list[k];
                    i.SetActive(serie.index, false);
                    i.yAxes[k].show = false;
                }
            }

            i.yAxis0.minMaxType = Axis.AxisMinMaxType.Custom;
        });
    }

    private void FixedUpdate()
    {
        if (Globle.IsStart && tmpCurCount != Globle.CurCount)
        {
            initCount++;
            if (initCount == intervalCnt)
            {
                foreach (var i in lc) AddOneData(i.name, i);
                initCount = 0;
            }

            tmpCurCount = Globle.CurCount;
        }

        // 如果isstart = false，刷新图表
        if (!Globle.IsStart & lc[0].series.GetSerie(0).dataCount != 0)
        {
            lc.ForEach(i => { i.ClearData(); });
            tmpCurCount = 0;
            m_TmpTimer = 0;
        }
    }

    void AddOneData(string mName, LineChart lineChart)
    {
        float xvalue = Globle.Normal[vihicleIndex - 1][Globle.CurCount].time;

        if (xvalue >= m_TmpTimer) m_TmpTimer = xvalue;
        else return;

        int mode = 0; // 1为wx 2为fwr 3为vihicle
        if (mName[0] == 'W') mode = 1;
        else if (mName[0] == 'F') mode = 2; // FL1LineChart 轴1左轮力
        else mode = 3;

        // 控制x轴splitNumber
        AdjustXSplitNumber(xvalue);

        if (mode == 1)
        {
            if (Globle.CurCount < Globle.Wx[vihicleIndex - 1].Count)
            {
                float yvalue = 0f;
                yvalue = Globle.Wx[vihicleIndex - 1][Globle.CurCount].wheelDis[mName[2] - '1'];

                lineChart.AddData(0, xvalue, yvalue);
                lineChart.yAxes[0].max = lineChart.yAxes[0].max > 0
                    ? lineChart.series.list[0].max * 1.3f
                    : lineChart.series.list[0].max * 0.7f;
                lineChart.yAxes[0].min = lineChart.yAxes[0].min < 0
                    ? lineChart.series.list[0].min * 1.3f
                    : lineChart.series.list[0].min * 0.7f;
            }
        }
        else if (mode == 2)
        {
            if (Globle.CurCount < Globle.Fwr[vihicleIndex - 1].Count)
            {
                float[] yvalue = new float[3];
                int idx;
                idx = mName[2] - '1';
                switch (mName[1])
                {
                    case 'L':
                        if (Globle.Fwr[vihicleIndex - 1][Globle.CurCount].vf != null)
                            yvalue[0] = Globle.Fwr[vihicleIndex - 1][Globle.CurCount].vf[idx];
                        if (Globle.Fwr[vihicleIndex - 1][Globle.CurCount].lf != null)
                            yvalue[1] = Globle.Fwr[vihicleIndex - 1][Globle.CurCount].lf[idx];
                        if (Globle.Fwr[vihicleIndex - 1][Globle.CurCount].hf != null)
                            yvalue[2] = Globle.Fwr[vihicleIndex - 1][Globle.CurCount].hf[idx];
                        break;
                    case 'R':
                        if (Globle.Fwr[vihicleIndex - 1][Globle.CurCount].vf != null)
                            yvalue[0] = Globle.Fwr[vihicleIndex - 1][Globle.CurCount].vf[idx + 4];
                        if (Globle.Fwr[vihicleIndex - 1][Globle.CurCount].lf != null)
                            yvalue[1] = Globle.Fwr[vihicleIndex - 1][Globle.CurCount].lf[idx + 4];
                        if (Globle.Fwr[vihicleIndex - 1][Globle.CurCount].hf != null)
                            yvalue[2] = Globle.Fwr[vihicleIndex - 1][Globle.CurCount].hf[idx + 4];
                        break;
                }

                for (int i = 0; i < 3; i++)
                {
                    lineChart.AddData(i, xvalue, yvalue[i]);
                    if (lineChart.series.list[i].show)
                    {
                        lineChart.yAxes[0].max = lineChart.yAxes[0].max > 0
                            ? lineChart.series.list[i].max * 1.3f
                            : lineChart.series.list[i].max * 0.7f;
                        lineChart.yAxes[0].min = lineChart.yAxes[0].min < 0
                            ? lineChart.series.list[i].min * 1.3f
                            : lineChart.series.list[i].min * 0.7f;
                    }
                    // m_lc.series.GetSerie(i).yAxisIndex = i == 1 ? 2 : i;
                }
            }
        }
        else
        {
            // 绘制加速度曲线
            if (Globle.CurCount < Globle.Vehicle[vihicleIndex - 1].Count)
            {
                float[] yvalue = new float[3];
                yvalue[0] = Globle.Vehicle[vihicleIndex - 1][Globle.CurCount].va;
                yvalue[1] = Globle.Vehicle[vihicleIndex - 1][Globle.CurCount].la;
                yvalue[2] = Globle.Vehicle[vihicleIndex - 1][Globle.CurCount].ha;
                for (int i = 0; i < 3; i++)
                {
                    lineChart.AddData(i, xvalue, yvalue[i]);
                    // m_lc.series.GetSerie(i).yAxisIndex = mName[0] != 'A' ? (i == 1 ? 2 : i) : 1;
                }
            }
        }
    }

    private void AdjustXSplitNumber(float xValue)
    {
        lc.ForEach(i => { i.xAxis0.splitNumber = (int) (xValue + 1f); });
    }

    void init(string mName)
    {
        int mode = 0; // 1为wx 2为fwr 3为vihicle
        if (mName[0] == 'W') mode = 1;
        else if (mName[0] == 'F') mode = 2; // FL1LineChart 轴1左轮力
        else mode = 3;
        if (mode == 1)
        {
            int idx = mName[2] - '1';
            string title = "轮对横移";
            string subTitle = $"轴{mName[2]}";
            lc[idx].title.text = title;
            lc[idx].title.subText = subTitle;
            lc[idx].series.GetSerie(0).lineStyle.color = new Color32(180, 0, 0, 255);
        }
        else if (mode == 2)
        {
            int idx = mName[2] - '1';
            if (mName[1] == 'L') idx *= 2;
            else idx = idx * 2 + 1;
            idx += 4;
            string title = "Wheel-Rail Force";//enzh"轮轨力";
            // string subTitle = $"轴{mName[2]}";
            // subTitle += mName[1] == 'L' ? '左' : '右';
            lc[idx].title.text = title;
            lc[idx].title.subText = "Left of Axle 1"; //enzh subTitle;
        }
        else
        {
            int idx = mName[2] - '1' + 12;
            string title = "Train Acceleration";//enzh"车体加速度";
            string subTitle = $"Train {mName[2]}";//enzh $"车{mName[2]}";
            lc[idx].title.text = title;
            lc[idx].title.subText = subTitle;
        }
    }


    public void StartProcess()
    {
        lc.ForEach(i => { i.ClearData(); });
    }
}