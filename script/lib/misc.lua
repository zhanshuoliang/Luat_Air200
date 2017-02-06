-- ��������
local string = require"string"
local ril = require"ril"
local sys = require"sys"
local base = _G
local os = require"os"
local io = require"io"
module(...)

local tonumber,tostring,print,req,smatch = base.tonumber,base.tostring,base.print,ril.request,string.match
local sn,snrdy,imeirdy,ver,imei,clkswitch,updating,dbging,flypending

local CCLK_QUERY_TIMER_PERIOD = 60*1000
local clk,calib,cbfunc={},false

local function rsp(cmd,success,response,intermediate)
	local prefix = string.match(cmd,"AT(%+%u+)")
	if cmd == "AT+WISN?" then
		sn = intermediate
		if not snrdy then sys.dispatch("SN_READY") snrdy = true end
	elseif cmd == "AT+VER" then
		ver = intermediate
	elseif cmd == "AT+CGSN" then
		imei = intermediate
		if not imeirdy then sys.dispatch("IMEI_READY") imeirdy = true end
	elseif smatch(cmd,"AT%+WIMEI=") then
	elseif smatch(cmd,"AT%+WISN=") then
		req("AT+WISN?")
	elseif prefix == "+CCLK" then
		startclktimer()
	elseif cmd == "AT+ATWMFT=99" then
		print('ATWMFT',intermediate)
		if intermediate == "SUCC" then
			calib = true
		else
			calib = false
		end
	elseif smatch(cmd,"AT%+CFUN=[01]") then
		sys.dispatch("FLYMODE_IND",smatch(cmd,"AT%+CFUN=(%d)")=="0")
	end
	if cbfunc then
		local tmp = cbfunc
		cbfunc = nil
		tmp(cmd,success,response,intermediate)
	end
end

function setclock(t,rspfunc)
	if t.year - 2000 > 38 then return end
	cbfunc = rspfunc
	req(string.format("AT+CCLK=\"%02d/%02d/%02d,%02d:%02d:%02d+32\"",string.sub(t.year,3,4),t.month,t.day,t.hour,t.min,t.sec),nil,rsp)
end

function getclockstr()
	clk = os.date("*t")
	clk.year = string.sub(clk.year,3,4)
	return string.format("%02d%02d%02d%02d%02d%02d",clk.year,clk.month,clk.day,clk.hour,clk.min,clk.sec)
end

function getweek()
	clk = os.date("*t")
	return ((clk.wday == 1) and 7 or (clk.wday - 1))
end

function getclock()
	return os.date("*t")
end

local CclkQueryTimerFun = function()
	startclktimer()
end

function startclktimer()
	if clkswitch or sys.getworkmode()==sys.FULL_MODE then
		sys.dispatch("CLOCK_IND")
		print('CLOCK_IND',os.date("*t").sec)
		sys.timer_start(CclkQueryTimerFun,(60-os.date("*t").sec)*1000)
	end
end

function changeclktimer()
	if clkswitch or sys.getworkmode()==sys.FULL_MODE then
		sys.timer_stop(startclktimer)
		sys.timer_start(CclkQueryTimerFun,(60-os.date("*t").sec)*1000)
	end
end

function setclkswitch(v)
	clkswitch = v
	if v then startclktimer() end
end

function getsn()
	return sn or ""
end

function getbasever()
	if ver ~= nil and base._INTERNAL_VERSION ~= nil then
		local d1,d2,bver,bprj,lver
		d1,d2,bver,bprj = string.find(ver,"_V(%d+)_(.+)")
		d1,d2,lver = string.find(base._INTERNAL_VERSION,"_V(%d+)")

		if bver ~= nil and bprj ~= nil and lver ~= nil then
			return "SW_V" .. lver .. "_" .. bprj .. "_B" .. bver
		end
	end
	return ""
end

function getimei()
	return imei or ""
end

function setflymode(val)
	if val then
		if updating or dbging then flypending = true return end
	end
	req("AT+CFUN="..(val and 0 or 1))
	flypending = false
end

function set(typ,val,cb)
	cbfunc = cb
	if typ == "WIMEI" or typ == "WISN" then
		req("AT+" .. typ .. "=\"" .. val .. "\"")
	elseif typ == "AMFAC" then
		req("AT+" .. typ .. "=" .. val)
	elseif typ == "CFUN" then
		req("AT+" .. typ .. "=" .. val)
	end
end

function getcalib()
	return calib
end

local function ind(id,para)
	if id=="SYS_WORKMODE_IND" then
		startclktimer()
	elseif id=="UPDATE_BEGIN_IND" then
		updating = true
	elseif id=="UPDATE_END_IND" then
		updating = false
		if flypending then setflymode(true) end
	elseif id=="DBG_BEGIN_IND" then
		dbging = true
	elseif id=="DBG_END_IND" then
		dbging = false
		if flypending then setflymode(true) end
	end

	return true
end

ril.regrsp("+ATWMFT",rsp)
ril.regrsp("+WISN",rsp)
ril.regrsp("+VER",rsp,4,"^[%w_]+$")
ril.regrsp("+CGSN",rsp)
ril.regrsp("+WIMEI",rsp)
ril.regrsp("+AMFAC",rsp)
ril.regrsp("+CFUN",rsp)
req("AT+ATWMFT=99")
req("AT+WISN?")
req("AT+VER")
req("AT+CGSN")
startclktimer()
sys.regapp(ind,"SYS_WORKMODE_IND","UPDATE_BEGIN_IND","UPDATE_END_IND","DBG_BEGIN_IND","DBG_END_IND")
