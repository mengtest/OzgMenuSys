
cfg = require("./cfg")
cmd = require("./cmd")
strings = require("./strings")
commons = require("./commons")
fs = require("fs")
sqlite3 = require("sqlite3").verbose()
im = require("imagemagick")

db = new sqlite3.Database(cfg.DB_PATH)

chkClientSql = "select * from client where ip = '{0}' and status = 1"
chkClientSql2 = "select * from client where ip = '{0}'" #检测订单是否归档的时候用到

clientList = new Array()
exports.clientList = clientList #客户端列表，里面的元素是connection对象

#公用方法不用exports
writeInformationDeskData = (dataStr, isAdmin) ->
	#向客户端或服务台发出数据
	
	if isAdmin == undefined
		isAdmin = 1

	sql = "select ip from client where is_admin = " + isAdmin
	db.all(sql, (err, rows) ->
		for item1 in rows
			for item2 in clientList
				if item1.ip == item2.remoteAddress
					item2.sendUTF(dataStr)
	)

exports.writeInformationDeskData = writeInformationDeskData

#公用方法不用exports
writeErrorIp = (connection) ->
	console.log("查询不到ip为" + connection.remoteAddress + "的数据")
	
	outputStr = commons.outputJsonStr(0, strings.CHECK_MSG1)
	
	connection.sendUTF(outputStr)
	connection.close()

#公用方法不用exports
writeDbData = (connection, sql, cmdStr) ->
	db.get(commons.format(chkClientSql, connection.remoteAddress), (err, row) ->
		if row != undefined && row
			db.all(sql, (err, rows) ->
				outputStr = commons.outputJsonStr(1, "", cmdStr, rows)
				connection.sendUTF(outputStr)
			)
		else
			#查询不到数据
			writeErrorIp(connection)
	)

#公用方法不用exports
getOrderDetailData = (connection) ->
	#返回订单明细列表，服务台用的
	sql = "select od.*, c.name as c_name from order_detail as od inner join `order` as o on od.order_id = o.id inner join client as c on o.client_id = c.id where o.status = 0 order by id asc limit 50"

	db.all(sql, (err, rows) ->
		outputStr = commons.outputJsonStr(1, null, cmd.CLIENT_WANT_ORDER_DETAIL, rows)
		connection.sendUTF(outputStr)
	)

#有链接时调用
exports.checkClient = (connection) ->
	
	db.get("select * from client where ip = '" + connection.remoteAddress + "'", (err, row) ->
		if row != undefined && row
			#console.log("已接收ip " + row.ip + "发来的数据:" + data)
			
			if row.is_admin == 1
				#服务台
				data = {
					"client": row
				}
				outputStr = commons.outputJsonStr(1, commons.format(strings.CHECK_MSG5, row.ip), cmd.CLIENT_WANT_TOMAIN, data)
				connection.sendUTF(outputStr)
			else
				#一般客户端
				if row.status == 0
					#未开通
					outputStr = commons.outputJsonStr(0, commons.format(strings.CHECK_MSG2, row.name))
					connection.sendUTF(outputStr)
				else if row.status == 1
					#已开通的逻辑
					
					#查询最新的一条订单数据
					sql = "select * from `order` where client_id = " + row.id + " order by id desc limit 1"
					db.get(sql, (err, row2) ->

						switch row2.status
							when 0
								#正在消费
								data = {
									"client": row
								}
								outputStr = commons.outputJsonStr(1, commons.format(strings.CHECK_MSG3, row.name), cmd.CLIENT_WANT_TOMENU, data)
								connection.sendUTF(outputStr)

								break
							when 1
								#结账中
								sql = "select sum(price) as total_price from order_detail where order_id = " + row2.id
								db.get(sql, (err, row3) ->
									outputStr = commons.outputJsonStr(1, commons.format(strings.MENU_PAYMENT_MSG1, row3.total_price), cmd.CLIENT_WANT_PAYMENT)
									connection.sendUTF(outputStr)
								)

								break
							when 2
								#归档

								#重新生成一条订单数据
								addTime = (new Date()).getTime() / 1000
								updateTime = addTime
								sql = "insert into `order` (add_time, update_time, client_id) values(" + parseInt(addTime) + ", " + parseInt(updateTime) + ", " + row.id + ")"
								db.run(sql)
								
								#向客户端返回数据
								data = {
									"client": row
								}
								outputStr = commons.outputJsonStr(1, commons.format(strings.CHECK_MSG3, row.name), cmd.CLIENT_WANT_TOMENU, data)
								connection.sendUTF(outputStr)

								break

					)
		else
			#查询不到数据
			writeErrorIp(connection)

	)

#获取菜单分类列表
exports.getMenuClassList = (connection) ->
	sql = "select * from menu_class order by id desc, sort desc"
	writeDbData(connection, sql, cmd.CLIENT_WANT_MENU_CLASS)

#获取一个菜单分类下面的菜单列表
exports.getMenuList = (connection, dataId) ->
	dataId = parseInt(dataId)

	sql = "select m.*, mc.name as mc_name from menu as m inner join menu_class as mc on m.class_id = mc.id where m.class_id = " + dataId + " order by m.id desc, m.sort desc"
	writeDbData(connection, sql, cmd.CLIENT_WANT_MENU)

#获取一个菜单的详细数据
#exports.getMenuDetail = (connection, dataId) ->
	#db.get(commons.format(chkClientSql, connection.remoteAddress), (err, row) ->
		#if row != undefined && row
			#dataId = parseInt(dataId)

			#db.get("select m.*, mc.name as mc_name from menu as m inner join menu_class as mc on m.class_id = mc.id where m.id = " + dataId, (err, row) ->

				#outputStr = commons.outputJsonStr(1, "", "", row)
				#connection.sendUTF(outputStr)
			#)
		#else
			#查询不到数据
			#writeErrorIp(connection)

	#)

#获取一个图片（公用方法不用exports）
getMenuImage = (connection, dataId, isSmall) ->
	
	db.get(commons.format(chkClientSql, connection.remoteAddress), (err, row) ->
		if row != undefined && row
			dataId = parseInt(dataId)

			db.get("select m.*, mc.name as mc_name from menu as m inner join menu_class as mc on m.class_id = mc.id where m.id = " + dataId, (err, row2) ->
				imgStr = null
				if isSmall
					imgStr = commons.fileBase64Encode("./" + row2.small_img)
				else 
					imgStr = commons.fileBase64Encode("./" + row2.big_img)

				data = {}
				data.img_base64str = imgStr
				data.menu_data = row2
				
				outputStr = null
				if isSmall
					outputStr = commons.outputJsonStr(1, null, cmd.CLIENT_WANT_SMALL_IMAGE, data)
				else
					outputStr = commons.outputJsonStr(1, null, cmd.CLIENT_WANT_BIG_IMAGE, data)
				connection.sendUTF(outputStr)
			)
		else
			#查询不到数据
			writeErrorIp(connection)
	)

#获取一个小图
exports.getMenuSmallImage = (connection, dataId) ->
	getMenuImage(connection, dataId, true)

#获取一个大图
exports.getMenuBigImage = (connection, dataId) ->	
	getMenuImage(connection, dataId, false)

#点菜
exports.addOrderDetail = (connection, menuId, quantity) ->
	
	if quantity == undefined || quantity == 0
		quantity = 1
	
	db.get(commons.format(chkClientSql, connection.remoteAddress), (err, row) ->
		if row != undefined && row
			menuId = parseInt(menuId)

			db.get("select * from menu where id = " + menuId, (err, row2) ->
				
				db.get("select id from `order` where client_id = " + row.id + " and status = 0 order by id desc, add_time desc limit 1", (err, row3) ->
					
					addTime = Date.parse(new Date()) / 1000
					
					quantity = commons.sqlValid(connection, quantity, strings.COMMONS_MSG2)
					if !quantity
						return

					db.run("insert into order_detail (add_time, menu_id, price, quantity, menu_name, order_id) values(" + addTime + ", " + row2.id + ", " + row2.price + ", " + quantity + ", '" + row2.name + "', " + row3.id + ")")
					
					updateTime = addTime
					db.run("update `order` set update_time = " + updateTime + " where id = " + row3.id)

					outputStr = commons.outputJsonStr(1, commons.format(strings.MENU_ADD_MSG, row2.name), cmd.CLIENT_WANT_ADDED_ORDER)
					connection.sendUTF(outputStr)

					#向服务台发出响应数据
					#刷新服务台的在线列表数据（该列表有消费总价格）
					outputStr = commons.outputJsonStr(1, null, cmd.CLIENT_GET_ONLINE_LIST)
					writeInformationDeskData(outputStr)
					
					#刷新服务台的菜单明细列表数据
					getOrderDetailData(connection)
				)
			)
		else
			#查询不到数据
			writeErrorIp(connection)

	)

#获取当前客户端的订单列表
exports.getOrderList = (connection) ->	
	sql = "select od.*, o.update_time as o_update_time from order_detail as od left join `order` as o on od.order_id = o.id left join client as c on o.client_id = c.id where c.ip = '" + connection.remoteAddress + "' and o.status = 0"
	writeDbData(connection, sql, cmd.CLIENT_WANT_ORDER_LIST)

#当前客户端结帐
exports.orderPayment = (connection) ->

	#订单状态：0正在消费，1结帐中，2完成订单
	
	db.get(commons.format(chkClientSql, connection.remoteAddress), (err, row) ->
		if row != undefined && row
			sql = "select sum(od.price * od.quantity) as total_price from order_detail as od left join `order` as o on od.order_id = o.id left join client as c on o.client_id = c.id where c.ip = '" + connection.remoteAddress + "' and o.status = 0"
			db.get(sql, (err, row2) ->
				if row2.total_price != null && row2.total_price > 0
					#改为结账中，完成订单是服务台操作的
					updateTime = (new Date()).getTime() / 1000

					sql = "update `order` set status = 1, update_time = " + parseInt(updateTime) + " where status = 0 and client_id = " + row.id
					db.run(sql)

					outputStr = commons.outputJsonStr(1, commons.format(strings.MENU_PAYMENT_MSG1, row2.total_price), cmd.CLIENT_WANT_PAYMENT)
					connection.sendUTF(outputStr)

					#向服务台发出响应数据
					#刷新服务台的数据
					outputStr = commons.outputJsonStr(1, null, cmd.CLIENT_GET_ONLINE_LIST)
					writeInformationDeskData(outputStr)
				else
					outputStr = commons.outputJsonStr(0, strings.MENU_PAYMENT_MSG2, cmd.CLIENT_WANT_PAYMENT)
					connection.sendUTF(outputStr)
			)
		else
			#查询不到数据
			writeErrorIp(connection)
	)

exports.openClient = (connection, targetClientIp) ->
	#服务台开通一个客户端
	db.get(commons.format(chkClientSql, connection.remoteAddress), (err, row) ->
		if row != undefined && row
			if row.is_admin == 1

				targetClientIp = commons.sqlValid(connection, targetClientIp, strings.COMMONS_MSG2)

				if !targetClientIp
					return

				db.get("select * from client where ip = '" + targetClientIp + "'", (err, row2) ->
					
					sql = "update client set status = 1 where ip = '" + targetClientIp + "'"
					db.run(sql)

					addTime = (new Date()).getTime() / 1000
					updateTime = addTime
					sql = "insert into `order` (add_time, update_time, client_id) values(" + parseInt(addTime) + ", " + parseInt(updateTime) + ", " + row2.id + ")"
					db.run(sql)
					
					#对目标客户端发送跳转命令
					data = {
						"client": row2
					}
					outputStr = commons.outputJsonStr(1, commons.format(strings.NOTICE_MSG1, row2.name), cmd.CLIENT_WANT_TOMENU, data)
					for item in clientList
						if targetClientIp == item.remoteAddress
							#console.log(outputStr)
							item.sendUTF(outputStr)
							break
					
					#返回服务台的信息
					outputStr = commons.outputJsonStr(1, commons.format(strings.NOTICE_MSG1, row2.name), cmd.CLIENT_GET_ONLINE_LIST)
					connection.sendUTF(outputStr)
				)
			else
				outputStr = commons.outputJsonStr(0, commons.format(strings.CHECK_MSG4, connection.remoteAddress))
				connection.sendUTF(outputStr)
		
		else
			#查询不到数据
			writeErrorIp(connection)
	)

exports.closeClient = (connection, targetClientIp) ->
	#服务台归档一个客户端
	db.get(commons.format(chkClientSql, connection.remoteAddress), (err, row) ->
		if row != undefined && row
			if row.is_admin == 1
				targetClientIp = commons.sqlValid(connection, targetClientIp, strings.COMMONS_MSG2)
				if !targetClientIp
					return

				db.get("select * from client where ip = '" + targetClientIp + "'", (err, row2) ->
					sql = "update client set status = 0 where ip = '" + targetClientIp + "'"
					db.run(sql)

					updateTime = (new Date()).getTime() / 1000
					sql = "update `order` set status = 2, update_time = " + parseInt(updateTime) + " where status = 1 and client_id = " + row2.id
					db.run(sql)

					outputStr = commons.outputJsonStr(1, commons.format(strings.NOTICE_MSG2, row2.name), cmd.CLIENT_WANT_TOMAIN)
					for item in clientList
						if targetClientIp == item.remoteAddress
							item.sendUTF(outputStr)
							break
					
					#返回服务台的信息
					outputStr = commons.outputJsonStr(1, commons.format(strings.NOTICE_MSG2, row2.name), cmd.CLIENT_GET_ONLINE_LIST)
					connection.sendUTF(outputStr)
				)
			else
				outputStr = commons.outputJsonStr(0, commons.format(strings.CHECK_MSG4, connection.remoteAddress))
				connection.sendUTF(outputStr)
		else
			#查询不到数据
			writeErrorIp(connection)
	)

#在线列表用到
statClientData = null
statClient = (connection, rows, i) ->
	
	db.get("select o.status as o_status, sum(od.price) as total_price from `order` as o left join order_detail as od on o.id = od.order_id where o.client_id = " + rows[i].id + " and o.status < 2", (err, row) ->
		if statClientData == null
			statClientData = new Array()

		statClientDataItem = {}
		statClientDataItem.o_status = row.o_status
		statClientDataItem.total_price = row.total_price
		statClientDataItem.ip = rows[i].ip
		statClientDataItem.name = rows[i].name
		statClientDataItem.status = rows[i].status
		statClientDataItem.is_admin = rows[i].is_admin
		statClientData.push(statClientDataItem)

		i++
		
		if i < rows.length
			statClient(connection, rows, i)
		else
			outputStr = commons.outputJsonStr(1, null, cmd.CLIENT_WANT_ONLINE_LIST, statClientData)
			connection.sendUTF(outputStr)
			statClientData = null
	)

exports.onlineList = (connection) ->
	#在线列表
	db.get(commons.format(chkClientSql, connection.remoteAddress), (err, row) ->
		if row != undefined && row
			if row.is_admin == 1
				ipList = new Array()
				for item in clientList
					ipList.push("'" + item.remoteAddress + "'")

				sql = "select * from client where ip in(" + ipList.toString() + ") order by id desc"
				db.all(sql, (err, rows) ->
					if rows.length > 0
						statClient(connection, rows, 0)
				)
			else
				outputStr = commons.outputJsonStr(0, commons.format(strings.CHECK_MSG4, connection.remoteAddress))
				connection.sendUTF(outputStr)
		else
			#查询不到数据
			writeErrorIp(connection)
	)

exports.orderDetailList = (connection) ->
	#下单明细列表
	db.get(commons.format(chkClientSql, connection.remoteAddress), (err, row) ->
		if row != undefined && row
			if row.is_admin == 1
				getOrderDetailData(connection)
			else
				outputStr = commons.outputJsonStr(0, commons.format(strings.CHECK_MSG4, connection.remoteAddress))
				connection.sendUTF(outputStr)
		else
			#查询不到数据
			writeErrorIp(connection)
	)

exports.orderDetailChangeStatus = (connection, dataId) ->
	#更新一个订单明细的状态（将状态改为1）
	db.get(commons.format(chkClientSql, connection.remoteAddress), (err, row) ->
		if row != undefined && row
			if row.is_admin == 1
				sql = "update order_detail set status = 1 where id = " + dataId
				db.run(sql)
				
				getOrderDetailData(connection)
			
			else
				outputStr = commons.outputJsonStr(0, commons.format(strings.CHECK_MSG4, connection.remoteAddress))
				connection.sendUTF(outputStr)
		else
			#查询不到数据
			writeErrorIp(connection)
	)

#日报表数据用到
reportDayData = null
getReportDay = (connection, timeFrom, timeTo) ->	
	if timeFrom <= timeTo
		tmpTimeTo = timeFrom + 86400
		sql = "select count(t.id) as total, sum(t.quantity) as total_quantity, sum(t.price) as total_price from (select o.id, o.add_time, sum(od.price) as price, sum(od.quantity) as quantity from `order` as o left join order_detail as od on o.id = od.order_id where o.add_time >= " + timeFrom + " and o.add_time <= " + tmpTimeTo + " group by od.order_id) as t"

		db.get(sql, (err, row) ->
			if reportDayData == null
				reportDayData = new Array()
			
			if row.total_price
				reportDayItem = {}
				reportDayItem.total = row.total
				reportDayItem.total_quantity = row.total_quantity
				reportDayItem.total_price = row.total_price
				reportDayItem.time = timeFrom
				reportDayData.push(reportDayItem)

			timeFrom = tmpTimeTo
			getReportDay(connection, timeFrom, timeTo)
		)	
	else
		outputStr = commons.outputJsonStr(1, null, cmd.CLIENT_WANT_REPORT_DAY, reportDayData)
		connection.sendUTF(outputStr)
		reportDayData = null

exports.reportDay = (connection, timeFrom, timeTo) ->
	#日报表数据
	db.get(commons.format(chkClientSql, connection.remoteAddress), (err, row) ->
		if row != undefined && row
			if row.is_admin == 1
				getReportDay(connection, timeFrom, timeTo)
			else
				outputStr = commons.outputJsonStr(0, commons.format(strings.CHECK_MSG4, connection.remoteAddress))
				connection.sendUTF(outputStr)
		else
			#查询不到数据
			writeErrorIp(connection)
	)

#月报表数据用到
reportMonthData = null
getReportMonth = (connection, timeFrom, timeTo) ->	
	if timeFrom <= timeTo
		d = new Date(timeFrom * 1000)
		d.setMonth(d.getMonth() + 1)
		
		tmpTimeTo = d.getTime() / 1000

		sql = "select count(t.id) as total, sum(t.quantity) as total_quantity, sum(t.price) as total_price from (select o.id, o.add_time, sum(od.price) as price, sum(od.quantity) as quantity from `order` as o left join order_detail as od on o.id = od.order_id where o.add_time >= " + timeFrom + " and o.add_time <= " + tmpTimeTo + " group by od.order_id) as t"

		db.get(sql, (err, row) ->
			if reportMonthData == null
				reportMonthData = new Array()
			
			if row.total_price
				reportMonthItem = {}
				reportMonthItem.total = row.total
				reportMonthItem.total_quantity = row.total_quantity
				reportMonthItem.total_price = row.total_price
				reportMonthItem.time = timeFrom
				reportMonthData.push(reportMonthItem)
			
			timeFrom = tmpTimeTo
			getReportMonth(connection, timeFrom, timeTo)
		)
	
	else
		outputStr = commons.outputJsonStr(1, null, cmd.CLIENT_WANT_REPORT_MONTH, reportMonthData)
		connection.sendUTF(outputStr)
		reportMonthData = null

exports.reportMonth = (connection, timeFrom, timeTo) ->
	#月报表数据
	db.get(commons.format(chkClientSql, connection.remoteAddress), (err, row) ->
		if row != undefined && row
			if row.is_admin == 1
				getReportMonth(connection, timeFrom, timeTo)
			else
				outputStr = commons.outputJsonStr(0, commons.format(strings.CHECK_MSG4, connection.remoteAddress))
				connection.sendUTF(outputStr)
		else
			#查询不到数据
			writeErrorIp(connection)
	)

exports.clientDataList = (connection) ->
	#获取客户端列表数据
	db.get(commons.format(chkClientSql, connection.remoteAddress), (err, row) ->
		if row != undefined && row
			if row.is_admin == 1
				sql = "select * from client order by id desc"
				db.all(sql, (err, rows) ->
					outputStr = commons.outputJsonStr(1, null, cmd.CLIENT_WANT_CLIENT_LIST, rows)
					connection.sendUTF(outputStr)
				)
			
			else
				outputStr = commons.outputJsonStr(0, commons.format(strings.CHECK_MSG4, connection.remoteAddress))
				connection.sendUTF(outputStr)
		else
			#查询不到数据
			writeErrorIp(connection)
	)

exports.clientDataAdd = (connection, data) ->
	#增加或更新客户端数据
	db.get(commons.format(chkClientSql, connection.remoteAddress), (err, row) ->
		if row != undefined && row
			if row.is_admin == 1
				data.ip = commons.sqlValid(connection, data.ip, strings.COMMONS_MSG2)
				data.name = commons.sqlValid(connection, data.name, strings.COMMONS_MSG2)
				data.is_admin = parseInt(data.is_admin)
				data.id = parseInt(data.id)

				if data.id == 0
					sql = "insert into client(ip, name, is_admin) values('" + data.ip + "', '" + data.name + "', " + data.is_admin + ")"
					db.run(sql)
				else
					sql = "update client set ip = '" + data.ip + "', name = '" + data.name + "', is_admin = " + data.is_admin + " where id = " + data.id
					db.run(sql)
				sql = "select * from client order by id desc"
				db.all(sql, (err, rows) ->
					outputStr = commons.outputJsonStr(1, null, cmd.CLIENT_WANT_CLIENT_LIST, rows)
					connection.sendUTF(outputStr)
				)
			else
				outputStr = commons.outputJsonStr(0, commons.format(strings.CHECK_MSG4, connection.remoteAddress))
				connection.sendUTF(outputStr)
		else
			#查询不到数据
			writeErrorIp(connection)
	)

exports.clientDataDelete = (connection, id) ->
	#删除客户端数据
	db.get(commons.format(chkClientSql, connection.remoteAddress), (err, row) ->
		if row != undefined && row
			if row.is_admin == 1
				id = parseInt(id)

				if id != 0
					sql = "delete from client where id = " + id
					db.run(sql)
				sql = "select * from client order by id desc"
				db.all(sql, (err, rows) ->
					outputStr = commons.outputJsonStr(1, null, cmd.CLIENT_WANT_CLIENT_LIST, rows)
					connection.sendUTF(outputStr)
				)
			else
				outputStr = commons.outputJsonStr(0, commons.format(strings.CHECK_MSG4, connection.remoteAddress))
				connection.sendUTF(outputStr)
		else
			#查询不到数据
			writeErrorIp(connection)
	)

exports.menuClassAdd = (connection, data) ->
	#增加或更新菜单分类数据
	db.get(commons.format(chkClientSql, connection.remoteAddress), (err, row) ->
		if row != undefined && row
			if row.is_admin == 1
				data.id = parseInt(data.id)
				data.name = commons.sqlValid(connection, data.name, strings.COMMONS_MSG2)

				if data.id == 0
					sql = "insert into menu_class(name) values('" + data.name + "')"
					db.run(sql)
				else
					sql = "update menu_class set name = '" + data.name + "' where id = " + data.id
					db.run(sql)
				
				sql = "select * from menu_class order by id desc"
				db.all(sql, (err, rows) ->
					outputStr = commons.outputJsonStr(1, null, cmd.CLIENT_WANT_MENU_CLASS, rows)

					#向服务台返回数据
					connection.sendUTF(outputStr)

					#向客户端返回数据
					writeInformationDeskData(outputStr, 0)
				)
				
			else
				outputStr = commons.outputJsonStr(0, commons.format(strings.CHECK_MSG4, connection.remoteAddress))
				connection.sendUTF(outputStr)
		
		else
			#查询不到数据
			writeErrorIp(connection)
	)

exports.menuClassDelete = (connection, id) ->
	#删除菜单分类数据
	db.get(commons.format(chkClientSql, connection.remoteAddress), (err, row) ->
		if row != undefined && row
			if row.is_admin == 1
				id = parseInt(id)

				if id != 0
					sql = "delete from menu_class where id = " + id
					db.run(sql)
					
					#删除该类下面的菜单
					sql = "delete from menu where class_id = " + id
					db.run(sql)
				

				sql = "select * from menu_class order by id desc"
				db.all(sql, (err, rows) ->
					outputStr = commons.outputJsonStr(1, null, cmd.CLIENT_WANT_MENU_CLASS, rows)

					#向服务台返回数据
					connection.sendUTF(outputStr)

					#向客户端返回数据
					writeInformationDeskData(outputStr, 0)
				)
			
			else
				outputStr = commons.outputJsonStr(0, commons.format(strings.CHECK_MSG4, connection.remoteAddress))
				connection.sendUTF(outputStr)
		else
			#查询不到数据
			writeErrorIp(connection)
		
	)

exports.menuAdd = (connection, data) ->
	#增加或更新菜单数据
	db.get(commons.format(chkClientSql, connection.remoteAddress), (err, row) ->
		if row != undefined && row
			if row.is_admin == 1
				imgBase64Str = data.img_base64str
				menuData = data.menu_data
				
				bigImg = null
				smallImg = null
				if imgBase64Str
					d = new Date()
					bigImg = "upload/" + d.format("yyyyMMddhhmmss") + ".jpg"
					smallImg = "upload/" + d.format("yyyyMMddhhmmss") + "_small.jpg"
					
					commons.fileBase64Decode(imgBase64Str, "./" + bigImg)

					#缩小图片
					im.resize({
						srcData: fs.readFileSync("./" + bigImg, "binary"),
						width: 350,
						height: 233
					}, 
					(err, stdout, stderr) ->
						if err
							throw err
						fs.writeFileSync("./" + smallImg, stdout, "binary")
						console.log("resized " + bigImg + " to fit within 350x233px")
					)
				
				menuData.name = commons.sqlValid(connection, menuData.name, strings.COMMONS_MSG2)
				menuData.price = parseFloat(menuData.price)
				menuData.class_id = parseInt(menuData.class_id)
				menuData.id = parseInt(menuData.id)

				sql = null
				if menuData.id == 0
					addTime = (new Date()).getTime() / 1000
										
					if bigImg == null
						sql = "insert into menu(name, price, add_time, class_id) values('" + menuData.name + "', " + menuData.price + ", " + parseInt(addTime) + ", " + menuData.class_id + ")"
					else
						sql = "insert into menu(name, price, add_time, class_id, big_img, small_img) values('" + menuData.name + "', " + menuData.price + ", " + parseInt(addTime) + ", " + menuData.class_id + ", '" + bigImg + "', '" + smallImg + "')"
					db.run(sql)
				else
					sql = null
					if bigImg == null
						sql = "update menu set name = '" + menuData.name + "', price = " + menuData.price + ", class_id = " + menuData.class_id + " where id = " + menuData.id
					else
						sql = "update menu set name = '" + menuData.name + "', price = " + menuData.price + ", class_id = " + menuData.class_id + ", big_img = '" + bigImg + "', small_img = '" + smallImg + "' where id = " + menuData.id
					db.run(sql)
					
				#向服务台返回数据
				outputStr = commons.outputJsonStr(1, null, cmd.CLIENT_WANT_SELECTED_MENU_CLASS, menuData.class_id)
				connection.sendUTF(outputStr)
			else
				outputStr = commons.outputJsonStr(0, commons.format(strings.CHECK_MSG4, connection.remoteAddress))
				connection.sendUTF(outputStr)
		else
			#查询不到数据
			writeErrorIp(connection)
	)

exports.menuDelete = (connection, id) ->
	#删除菜单分类数据
	db.get(commons.format(chkClientSql, connection.remoteAddress), (err, row) ->
		if row != undefined && row
			if row.is_admin == 1
				
				id = parseInt(id)

				if id != 0
					db.get("select * from menu where id = " + id, (err, row2) ->
						sql = "delete from menu where id = " + id
						db.run(sql)

						#向服务台返回数据
						outputStr = commons.outputJsonStr(1, null, cmd.CLIENT_WANT_SELECTED_MENU_CLASS, row2.class_id)
						connection.sendUTF(outputStr)
					)
			
			else
				outputStr = commons.outputJsonStr(0, commons.format(strings.CHECK_MSG4, connection.remoteAddress))
				connection.sendUTF(outputStr)
		else
			#查询不到数据
			writeErrorIp(connection)
	)
