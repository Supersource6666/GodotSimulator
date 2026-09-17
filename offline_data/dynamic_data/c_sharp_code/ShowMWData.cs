using System;
using System.Collections;
using System.Collections.Generic;
using General;
using SubwaySimulation.Utils;
using TMPro;
using UnityEngine;
using UnityEngine.UI;

[Serializable]
public class TextList
{
    public List<TMP_Text> Texts;
}

// 单节车的“可移动窗口”可见性
[Serializable]
public class SingleVihicleMWText
{
    public List<TMP_Text> accText;
    public List<TextList> fwrText;
    public List<TextList> wxText;
}

public class ShowMWData : MonoBehaviour
{
    [SerializeField] private List<SingleVihicleMWText> m_MWTexts;
    [SerializeField] private TMP_FontAsset m_MWFont;
    [SerializeField] private int Interval = 20;

    private int tmpCurCount = -1;
    private int counter;

    private void Start()
    {
        m_MWTexts.ForEach((i) =>
        {
            i.accText.ForEach((t) => { t.font = m_MWFont; });
            i.fwrText.ForEach((t) => { t.Texts.ForEach(item => { item.font = m_MWFont; }); });
            i.wxText.ForEach((t) => { t.Texts.ForEach(item => { item.font = m_MWFont; }); });
        });
    }

    private void FixedUpdate()
    {
        if (Globle.IsStart && tmpCurCount != Globle.CurCount && counter++ % Interval == 0)
        {
            DataShow();
            tmpCurCount = Globle.CurCount;
        }
    }

    private void DataShow()
    {
        if (Globle.CurCount < 0) return;
        for (var i = 0; i < Globle.NumVihicle; i++)
        {
            if (i >= m_MWTexts.Count) continue;

            // 三向加速度数据
            if (i < Globle.Vehicle.Count && Globle.Vehicle[i].Count > Globle.CurCount)
            {
                m_MWTexts[i].accText[0].text = Globle.Vehicle[i][Globle.CurCount].va.ToString("F6");
                m_MWTexts[i].accText[1].text = Globle.Vehicle[i][Globle.CurCount].la.ToString("F6");
                m_MWTexts[i].accText[2].text = Globle.Vehicle[i][Globle.CurCount].ha.ToString("F6");
            }

            // 力数据
            if (i < Globle.Fwr.Count && Globle.Fwr[i].Count > Globle.CurCount)
                for (var k = 0; k < 8; k++)
                {
                    var fwr = Globle.Fwr[i][Globle.CurCount];
                    if (fwr.vf != null && k < fwr.vf.Length)
                        m_MWTexts[i].fwrText[k].Texts[0].text = fwr.vf[k].ToString("F6");
                    if (fwr.lf != null && k < fwr.lf.Length)
                        m_MWTexts[i].fwrText[k].Texts[1].text = fwr.lf[k].ToString("F6");
                    if (fwr.hf != null && k < fwr.hf.Length)
                        m_MWTexts[i].fwrText[k].Texts[2].text = fwr.hf[k].ToString("F6");
                }

            // 横移数据
            if (i < Globle.Wx.Count && Globle.Wx[i].Count > Globle.CurCount && i < Globle.Normal.Count && Globle.Normal[i].Count > Globle.CurCount)
                for (var k = 0; k < 4; k++)
                {
                    m_MWTexts[i].wxText[k].Texts[0].text = Globle.Normal[i][Globle.CurCount].velocity.ToString("F6");
                    if (Globle.Wx[i][Globle.CurCount].wheelDis != null && k < Globle.Wx[i][Globle.CurCount].wheelDis.Count)
                        m_MWTexts[i].wxText[k].Texts[1].text = Globle.Wx[i][Globle.CurCount].wheelDis[k].ToString("F6");
                }
        }
    }
}