using System;
using General;
using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.UI;
using XCharts;

public class DataRange : MonoBehaviour, IDragHandler, IEndDragHandler
{
    [SerializeField] private GameObject Canvas;
    private LineChart[] m_LineCharts;
    private Slider m_Slider;
    private int m_Range;
    private float m_Max;
    private float m_Min;

    private void Awake()
    {
        m_Slider = GameObject.Find("Canvas/DataRangeSlider").GetComponent<Slider>();
        m_Slider.onValueChanged.AddListener((val) =>
        {
            Globle.DataRange = (int) (val * Globle.CountData);
            m_Range = Globle.DataRange;
            Debug.Log($"AdjustDataRange range: {m_Range}");
            Debug.Log($"AdjustDataRange Globle.dataRange: {Globle.DataRange}");
        });
        m_LineCharts = Canvas.GetComponentsInChildren<LineChart>();

        CloseAll();
    }

    private void CloseAll()
    {
        foreach (var item in m_LineCharts)
        {
            if (item.transform.parent.name != "Content")
            {
                // 只关闭MWSet中的
                item.transform.parent.gameObject.SetActive(false);
            }
        }
    }

    private void AdjustDataRange()
    {
        var maxIndex = Globle.CurCount + m_Range / 2 >= Globle.Normal[0].Count ? Globle.Normal[0].Count-1 : Globle.CurCount + m_Range / 2;
        m_Max = Globle.Normal[0][maxIndex].time;
        var minIndex = Globle.CurCount - m_Range / 2 < 0 ? 0 : Globle.CurCount - m_Range / 2;
        m_Min = Globle.Normal[0][minIndex].time;
        Debug.Log($"AdjustDataRange curcount: {Globle.CurCount}");
        Debug.Log($"AdjustDataRange max: {m_Max}");
        Debug.Log($"AdjustDataRange min: {m_Min}");
        foreach (var item in m_LineCharts)
        {
            item.xAxis0.min = m_Min;
            item.xAxis0.max = m_Max;
        }
    }
    
    public void OnDrag(PointerEventData eventData)
    {
    }

    /// <summary>
    /// 给 Slider 添加结束拖拽事件    当拖拽结束后触发
    /// </summary>
    /// <param name="eventData"></param>
    public void OnEndDrag(PointerEventData eventData)
    {
        if (Globle.CountData == 0)
        {
            return;
        }
        AdjustDataRange();
    }
}