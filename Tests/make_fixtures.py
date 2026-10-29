# -*- coding: utf-8 -*-
"""Small OOXML test fixtures, not user workbooks. No third-party runtime required."""
from pathlib import Path
from xml.sax.saxutils import escape
from zipfile import ZipFile, ZIP_DEFLATED
root = Path(__file__).resolve().parents[1] / 'build' / 'verification' / 'fixtures'; root.mkdir(parents=True, exist_ok=True)

def make(name, rows):
    xml_rows=[]
    for r,row in enumerate(rows,1):
        cells=[]
        for c,value in enumerate(row):
            ref=chr(65+c)+str(r)
            if isinstance(value,float):
                cells.append(f'<c r="{ref}"><v>{value}</v></c>')
            else:
                cells.append(f'<c r="{ref}" t="inlineStr"><is><t>{escape(str(value))}</t></is></c>')
        xml_rows.append(f'<row r="{r}">'+''.join(cells)+'</row>')
    sheet='<?xml version="1.0" encoding="UTF-8"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>'+''.join(xml_rows)+'</sheetData></worksheet>'
    with ZipFile(root/name,'w',ZIP_DEFLATED) as z:
        z.writestr('[Content_Types].xml','<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>')
        z.writestr('_rels/.rels','<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>')
        z.writestr('xl/workbook.xml','<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="课表" sheetId="1" r:id="rId1"/></sheets></workbook>')
        z.writestr('xl/_rels/workbook.xml.rels','<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/></Relationships>')
        z.writestr('xl/worksheets/sheet1.xml',sheet)
make('list.xlsx',[
 ['课程名称','星期','时段','开始时间','结束时间','教室','单双周'],
 ['数据结构','周一','上午',0.375,640/1440,'A203','单周'],
 ['算法','周四','下午','14:00','15:40','B101','每周']])
make('grid.xlsx',[
 ['时段','周一','周二','周三','周四','周五'],
 ['上午','数学','','','',''],
 ['晚上','','算法','','','']])

make('complex.xlsx',[
 ['时段','节次','上课时间','周一','周二','周三','周四','周五','周六','周日'],
 ['上午','1','09:00~09:45','创意工作坊','','','创意工作坊','','',''],
 ['上午','2','09:55~10:40','创意工作坊','','','创意工作坊','','',''],
 ['晚上','9','19:00~19:45','','','学习分享','','','',''],
 ['晚上','10','19:55~20:40','','','学习分享','','','',''],
 ['','','','','','','','','',''],
 ['课程明细','','','','','','','','',''],
 ['序号','课程名称','上课时间','上课地点','周次','','','','',''],
 ['1','创意工作坊','周一1-2节；周四1-2节','示例教室','周一1,2,3,5；周四1,2,4,5','','','','',''],
 ['2','学习分享','周三19:00~20:40','线上','1-3,5-8；第4周为周六','','','','',''],
 ['说明：这里是非课程文字，不能导入','','','','','','','','','']])
